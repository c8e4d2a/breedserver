defmodule Bobo.Ergnode do
  use GenServer
  require Logger
  import Ecto.Query

  @mint_attrlist [:id, :ipfs,:mint_tx,:receiver_address,:name,:token_id,:is_creature,:is_scroll,:from_ritual_id,:cd_minutes,:last_use,:gen,:parents,
    :lease_price,:after_lease_return_to_owner,:burn_tx,:creature_name,:project, :inserted_at, :updated_at]
  @slot_attrlist [
    :own_creature_token_id,
    :request_creature_token_id,
    :return_creature_on_token_release,
    :bid_erg,
    :assigned_creature_token_id,
    :scroll_id,
    :inserted_at,
    :updated_at,
    :done]
  @node_url "http://127.0.0.1:9053"
  @node_api_key "yourapikey"
  @tree "0008cd0315a3a710c4e8d6ecad213636428c4d8d49ac73d248deaffb895730b37ddacc37"
  @change_address "9gdLSKyzeyB3qQ1LWidALiyyfvQwFCZtcozXqjQ9hRkfGwPFCbR"
  @projects ["inferno", "bitmasks", "wooden"]
  @min_breed_fee 30000000
  @js_scripts_home "/home/node/scroll/"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    ## TODO: rescan wallet every 10min
    handle_unspent_wallet_boxes()
    schedule_work()
    {:ok, state}
  end

  def handle_info(:work, state) do
    schedule_work()
    {:noreply, state}
  end

  defp handle_unspent_wallet_boxes() do
    {:ok, %{:body => body, :status => 200}} =
      SimpleHttp.get(@node_url <> "/wallet/boxes/unspent?minConfirmations=-1",
        headers: %{
          "Content-Type" => "application/json",
          "api_key" => @node_api_key
        }
      )

    boxes = Jason.decode!(body) |> Enum.map(fn x -> Map.get(x,"box")end)
    process_boxes(boxes)
  end

  defp schedule_work() do
    {:ok, %{:body => body, :status => 200}} =
      SimpleHttp.post(
        @node_url <> "/transactions/unconfirmed/outputs/byErgoTree?limit=100&offset=0",
        body:
          Jason.encode!(@tree),
        headers: %{
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        },
        timeout: 1000,
        connect_timeout: 1000
      )

    unconfirmedBoxes = Jason.decode!(body)
    process_boxes(unconfirmedBoxes)


    # In 5 sec
    Process.send_after(self(), :work, 5 * 1000)
  end

  def process_boxes(boxes) do
    boxes
    |> Enum.each(&handle_each_box/1)
  end

  def handle_each_box(box) do
    trash    = Bobo.Repo.get_by(Bobo.TrashBox, box_id: Map.get(box, "boxId"))
    #nftboxes   = Bobo.Repo.all(Bobo.Mint, payment_box_id: Map.get(box, "boxId"))
    #leaseboxes = Bobo.Repo.all(Bobo.Mint, lease_box_id: Map.get(box, "boxId"))
    #if is_nil(trash) && length(nftboxes)==0 && length(leaseboxes)==0 do
    if is_nil(trash) do
      handle_unhandled_box(box, box)
    end
  end

  def handle_unhandled_box( %{
    "additionalRegisters" => %{},
    "assets" => [
      %{
        "amount" => 1,
        "tokenId" => tokenId1
      },
      %{
        "amount" => 1,
        "tokenId" => tokenId2
      }
    ],
    "boxId" => boxId,
    "value" => value
  }, box ) do
    Logger.info("potential ritual init " <> boxId)

    mints = Bobo.Mint
    |> where(token_id: ^tokenId1)
    |> or_where(token_id: ^tokenId2)
    |> Bobo.Repo.all

    types = mints |> Enum.map(fn x ->
      if x.is_creature do
        :creature
      else if x.is_scroll do
        :scroll
          end
      end
    end) |> Enum.sort()
    projects = mints |> Enum.map(fn x -> x.project end) |> MapSet.new |> MapSet.to_list()
    #TODO
    if [:creature, :scroll] == types && length(projects) == 1 && Enum.member?(@projects, Enum.at(projects,0)) && value >= @min_breed_fee do
      creatureId = mints |> Enum.filter(fn x -> x.is_creature && is_off_cooldown(x) && x.breed_in_progress != true end) |> Enum.map(fn x -> x.id end) |> Enum.at(0)
      scrollId = mints |> Enum.filter(fn x -> x.is_scroll end) |> Enum.map(fn x -> x.id end) |> Enum.at(0)
      if creatureId != nil do
        # fill in db
        tribute = value - @min_breed_fee
        address = get_box_sender_address(box)
        if address do
          set_breed_in_progress(creatureId)
          initialize_ritual_slots(scrollId, creatureId, tribute, boxId, address)
          BoboWeb.Endpoint.broadcast("room:lobby", "half_ritual", %{:scroll_id => scrollId, :creature_id => creatureId, :tribute => tribute, :address => address} )
        end
        #BoboWeb.Endpoint.broadcast("room:lobby", "half_ritual", %{:scroll_id => 125, :creature_id => 5, :tribute => 10000000000} )
      end
    else
      box_to_trash boxId
    end
  end

  def handle_unhandled_box( %{
    "additionalRegisters" => %{},
    "assets" => [
      %{
        "amount" => 1,
        "tokenId" => tokenId1
      }
    ],
    "boxId" => boxId,
    "value" => value
  }, box ) do
    Logger.info("potential creature lease/ritual config " <> boxId)
    Logger.info("#{inspect(box)}")
    # check if token is a scroll or creature
    mint = Bobo.Repo.get_by(Bobo.Mint, token_id: tokenId1)

    Logger.info("value: #{inspect(value)}")
    Logger.info("mint: #{inspect(mint)}")
    if mint && mint.is_creature && value >= @min_breed_fee do
      ritualId = value - @min_breed_fee
      ritual = Bobo.Repo.get_by(Bobo.Mint, id: ritualId)
      if ritual && ritual.is_scroll && ritual.burn_tx == nil do
        slots = Bobo.Slot |> where(scroll_id: ^ritualId) |> Bobo.Repo.all
        if(length(slots) == 2) do
           slot = Enum.find(slots, fn s -> s.assigned_creature_token_id == nil && s.bid_erg > 0 end)
           address = get_box_sender_address(box)
           Logger.info("slots: #{inspect(slots)}")
           Logger.info("address: #{address}")
           if slot do
              if address do
                Logger.warn("ACHTUNG ACHTUNG!!!!!")
                Bobo.Mint.changeset(mint,%{
                  :receiver_address => address,
                  :lease_box_id => Map.get(box, "boxId"),
                  :after_lease_return_to_owner => true,
                  :lease_price => nil,
                  :release_in_progress => false,
                  :release_tx => nil
                }) |> Bobo.Repo.update()
                |>IO.inspect()

                Bobo.Slot.changeset(slot, %{
                  :assigned_creature_token_id => tokenId1,
                  :return_creature_on_token_release => true
                }) |> Bobo.Repo.update()
                |>IO.inspect()
              end
           end
           if address do
              Bobo.Slot |> where(scroll_id: ^ritualId) |> Bobo.Repo.all |> start_ritual_if_slots_ready
           end
          end
      end
      #check if creature should be inserted into a slot

      # this is an insertion, meaning we insert a creature if a slot in the database exists where
      # amount fits the tribute

    end
  end


  def handle_unhandled_box( %{
    "additionalRegisters" => %{},
    "assets" => [
      %{
        "amount" => 1,
        "tokenId" => tokenId1
      },
      %{
        "amount" => 1,
        "tokenId" => tokenId2
      },
      %{
        "amount" => 1,
        "tokenId" => tokenId3
      }
    ],
    "boxId" => boxId,
    "value" => 30000000
  }, box) do
    Logger.info("potential breeding box " <> boxId)

    mints = Bobo.Mint
    |> where(token_id: ^tokenId1)
    |> or_where(token_id: ^tokenId2)
    |> or_where(token_id: ^tokenId3)
    |> Bobo.Repo.all

    types = mints |> Enum.map(fn x ->
      if x.is_creature do
        :creature
      else if x.is_scroll do
        :scroll
          end
      end
    end) |> Enum.sort()
    projects = mints |> Enum.map(fn x -> x.project end) |> MapSet.new |> MapSet.to_list()

    if [:creature, :creature, :scroll] == types && length(projects) == 1 && Enum.member?(@projects, Enum.at(projects,0)) do
      creaturesIds = mints |> Enum.filter(fn x -> x.is_creature && is_off_cooldown(x) && x.breed_in_progress != true end) |> Enum.map(fn x -> x.id end)
      scrollId = mints |> Enum.filter(fn x -> x.is_scroll end) |> Enum.map(fn x -> x.id end) |> Enum.at(0)
      with [id1, id2] <- creaturesIds do
        set_breed_in_progress(id1, id2)
        meta = breed_creature_json(scrollId, id1, id2)
        if nil != meta do
          breedFromSingleBox(scrollId, id1, id2, meta, box)
        else
          cancel_breed_in_progress(id1, id2)
        end
      end
    else
      box_to_trash boxId
    end
  end


  def start_ritual_if_slots_ready(ritualSlots) do
    Logger.info("start_ritual_if_slots_ready #{inspect(ritualSlots)}")
    if length(Enum.filter(ritualSlots, fn s-> s.assigned_creature_token_id != nil && !s.done end)) == 2 do
      slot0 = Enum.at(ritualSlots, 0)
      slot1 = Enum.at(ritualSlots, 1)
      mints = Bobo.Mint
      |> where(token_id: ^slot0.assigned_creature_token_id)
      |> or_where(token_id: ^slot1.assigned_creature_token_id)
      |> Bobo.Repo.all
      if length(mints |> Enum.filter(&is_off_cooldown/1)) == 2 do
          breed_from_2_slots(ritualSlots)
      end
    end
  end

  def initialize_ritual_slots(scrollId, creatureId, payout, boxId, address) do
    from(s in Bobo.Slot, where: s.scroll_id == ^scrollId) |> Bobo.Repo.delete_all

    %Bobo.Mint{:token_id => token_1_id} = Bobo.Repo.get_by(Bobo.Mint, id: creatureId)

    Bobo.Slot.changeset(%Bobo.Slot{}, %{
      :own_creature_token_id => token_1_id,
      :assigned_creature_token_id => token_1_id,
      :return_creature_on_token_release => true,
      :scroll_id => scrollId,
    })
    |> Bobo.Repo.insert()

    Bobo.Slot.changeset(%Bobo.Slot{}, %{
      :bid_erg => payout,
      :scroll_id => scrollId,
    })
    |> Bobo.Repo.insert()

    Bobo.Repo.get_by(Bobo.Mint, id: scrollId)
    |> Bobo.Mint.changeset(%{
      :lease_box_id => boxId,
      :receiver_address => address
    })
    |> Bobo.Repo.update()

    Bobo.Repo.get_by(Bobo.Mint, id: creatureId)
    |> Bobo.Mint.changeset(%{
      :lease_box_id => boxId,
      :receiver_address => address,
      :after_lease_return_to_owner => true,
      :lease_price => nil,
      :release_in_progress => false,
      :release_tx => nil
    })
    |> Bobo.Repo.update()

    Logger.info("Ritual slots inserted for scrollId #{scrollId}")
  end

  def handle_unhandled_box(box, box) do
    # find out what to do with this box
    nanoErgs = Map.get(box, "value")
    boxId = Map.get(box, "boxId")

    # %Bobo.Mint{}
    meta = get_mint_id_by_nano_erg(nanoErgs, boxId)

    if meta do
      eip4regs = %{
        name: meta.name,
        description: "inferno.black",
        url: meta.ipfs,
        sha256: ""
      }

      mintnft(box, eip4regs)
    end
  end

  def breed_from_2_slots([%{:scroll_id => scrollId, :assigned_creature_token_id => tokenId1, :bid_erg => tokenId1BidErg}, %{:assigned_creature_token_id => tokenId2, :bid_erg => tokenId2BidErg}]) do
    Logger.info("breed_from_2_slots #{inspect([%{:scroll_id => scrollId, :assigned_creature_token_id => tokenId1, :bid_erg => tokenId1BidErg}, %{:assigned_creature_token_id => tokenId2, :bid_erg => tokenId2BidErg}])}")
    # burn scroll!
    # return each creature to owner
    # mints new inferno

    #when receiving a scroll make sure to save: receiver_address, lease_box_id
    #when receiving a creature: receiver_address, lease_box_id
    %Bobo.Mint{:token_id => scrollTokenId, :receiver_address => receiverScroll, :lease_box_id => scrollBox} = Bobo.Repo.get_by(Bobo.Mint, id: scrollId)
    %Bobo.Mint{:id => id1, :receiver_address => receiver1, :lease_box_id => receiver1Box} = Bobo.Repo.get_by(Bobo.Mint, token_id: tokenId1)
    %Bobo.Mint{:id => id2, :receiver_address => receiver2, :lease_box_id => receiver2Box} = Bobo.Repo.get_by(Bobo.Mint, token_id: tokenId2)

    set_breed_in_progress(id1, id2)
    meta = breed_creature_json(scrollId, id1, id2)
    if nil != meta do
      IO.inspect(meta)
      requiredBoxIds = [scrollBox, receiver1Box, receiver2Box]
      relevantBoxes = Enum.filter(fetch_all_wallet_boxes(), fn box-> Enum.member?(requiredBoxIds, Map.get(box,"boxId")) end)
      scrollBoxData = Enum.filter(fetch_all_wallet_boxes(), fn box-> Enum.member?([scrollBox], Map.get(box,"boxId")) end) |> Enum.at(0)

      Logger.info("receiver1: #{receiver1}, tokenId1: #{tokenId1}")
      Logger.info("receiver2: #{receiver2}, tokenId2: #{tokenId2}")
      breedFromMultipleBoxes(scrollBoxData, scrollId, id1, id2, scrollTokenId, receiverScroll, tokenId1, receiver1, tokenId1BidErg, tokenId2, receiver2, tokenId2BidErg, meta, relevantBoxes)
    else
      cancel_breed_in_progress(id1, id2)
    end

  end

  def breed_creature_json(scrollId, id1, id2) do
      set_breed_in_progress(id1, id2)

      breedResponse = System.cmd("node", ["#{@js_scripts_home}breedInfernoCli.js", "#{scrollId}", "#{id1}", "#{id2}"])
      case breedResponse do
        {creature_string, 0} ->
          {:ok, creature} = Jason.decode(creature_string, keys: :atoms)
          creature
        _ -> nil
      end
  end

  defp set_breed_in_progress(id) do
    Bobo.Repo.get_by(Bobo.Mint, id: id)
    |> Bobo.Mint.changeset(%{
      :breed_in_progress => true
    })
    |> Bobo.Repo.update()
  end

  defp set_breed_in_progress(id1, id2) do
    set_breed_in_progress(id1)
    set_breed_in_progress(id2)
  end

  defp cancel_breed_in_progress(id1, id2) do
    Bobo.Repo.get_by(Bobo.Mint, id: id1)
    |> Bobo.Mint.changeset(%{
      :breed_in_progress => false
    })
    |> Bobo.Repo.update()

    Bobo.Repo.get_by(Bobo.Mint, id: id2)
    |> Bobo.Mint.changeset(%{
      :breed_in_progress => false
    })
    |> Bobo.Repo.update()
  end

  defp box_to_trash boxId do
    Bobo.TrashBox.changeset(%Bobo.TrashBox{}, %{
      :box_id => boxId
    })
    |> Bobo.Repo.insert()
  end

  defp is_off_cooldown(%{:cd_minutes => cd_minutes, :last_use => last_use}) do
    if nil == last_use  do
      true
    else
      {:ok, time} = DateTime.from_naive(last_use, "Etc/UTC")
      unix_last_use = DateTime.to_unix(time)
      (unix_last_use + cd_minutes *  60) < DateTime.to_unix(DateTime.utc_now())
    end
  end

  def get_mint_id_by_nano_erg(nanoErgs, boxId) do
    mintId = get_mint_id(nanoErgs)
    if mintId != nil do
      case insert_new_mintbox(mintId, boxId) do
        {:ok, mint} -> mint
        _ -> nil
      end
    else
      nil
    end
  end

  # returns %Bobo.Mint{}
  def insert_new_mintbox(mintId, boxId) do
    try do
      result =
        Bobo.Nftbox.changeset(%Bobo.Nftbox{}, %{
          :mint_id => mintId,
          :box_id => boxId
        })
        |> Bobo.Repo.insert()

      with {:ok, nftbox} <- result do
        Bobo.Repo.get_by(Bobo.Mint, id: nftbox.mint_id)
        |> Bobo.Mint.changeset(%{
          :payment_box_id => nftbox.box_id
        })
        |> Bobo.Repo.update()
      end
    catch
      e -> Logger.error(e)
    end

  end

  def get_mint_id(nanoErgs) do
    query =
      "select id from mints where mints.mint_price_in_nano_erg = #{nanoErgs} and mints.payment_box_id is null limit 1;"

    {:ok, %{:rows => rows, :num_rows => num_rows}} = Ecto.Adapters.SQL.query(Bobo.Repo, query)

    case num_rows do
      1 ->
        rows |> Enum.at(0) |> Enum.at(0)
      _ ->
        nil
    end
  end

  def breedFromSingleBox(scrollId, id1, id2, meta, box) do
    address = get_box_sender_address(box)
    %Bobo.Mint{:token_id => token_1_id} = Bobo.Repo.get_by(Bobo.Mint, id: meta.parent1)
    %Bobo.Mint{:token_id => token_2_id} = Bobo.Repo.get_by(Bobo.Mint, id: meta.parent2)
    %Bobo.Mint{:token_id => scroll_token_id} = Bobo.Repo.get_by(Bobo.Mint, id: meta.scrollId)

    if nil != address do
      mint_creature_and_burn_scroll_deprecated(scrollId, id1, id2, scroll_token_id, token_1_id, token_2_id, meta, box, address)
    else
      cancel_breed_in_progress(id1, id2)
    end
  end

  def breedFromMultipleBoxes(scrollBox, scrollId, id1, id2, scrollTokenId, receiverScroll, tokenId1, receiver1, tokenId1BidErg, tokenId2, receiver2, tokenId2BidErg, meta, boxes) do
    mint_creature_and_burn_scroll(scrollBox, scrollId, id1, id2, scrollTokenId, receiverScroll, tokenId1, receiver1, tokenId1BidErg, tokenId2, receiver2, tokenId2BidErg, meta, boxes)
  end

  def mint_creature_and_burn_scroll(scrollBox, scrollId, id1, id2, scrollTokenId, receiverScroll, tokenId1, receiver1, tokenId1BidErg, tokenId2, receiver2, tokenId2BidErg, meta, boxes) do

    eip4regs = %{
      name: meta.name,
      description: "{\"721\":{\"#{meta.name}\": {\"Name\": \"#{meta.name}\",\"Gen\": #{meta.gen}}}}",
      url: meta.ipfs,
      sha256: meta.sha256
    }

    height = get_height()

    txMeta = %{
      :scrollTokenId => scrollTokenId,
      :scrollAddress => receiverScroll,
      :token1Id => tokenId1,
      :token1Address => receiver1,
      :token1AddErg => tokenId1BidErg,
      :token2Id => tokenId2,
      :token2Address => receiver2,
      :token2AddErg => tokenId2BidErg,
      :changeAddress => @change_address,
      :outputValue => "1000000",
      :txFee => "1110000",
      :height => height,
      :eip4Regs => eip4regs,
      :inputBoxes => boxes
    }

    {:ok, encoded} = Jason.encode(txMeta)

    Logger.info "tx meta:"
    Logger.info encoded

    signResponse = System.cmd("node", ["#{@js_scripts_home}mintCreatureMultiboxUnsignedTx.js", encoded])

    Logger.info "signResponse:"
    IO.inspect signResponse
    case signResponse do
      {unsigned_tx_string, 0} ->
        {:ok, unsigned_tx} = Jason.decode(unsigned_tx_string)
        Logger.info("unsigned tx #{unsigned_tx_string}")

        signedTx = sign_creature_mint_tx(unsigned_tx)
        #  |> send_tx
        if signedTx != nil do
          Logger.info("signed tx #{Jason.encode!(signedTx)}")
          #txId = nil
          txId = send_tx(signedTx)

          if nil != txId do
            Logger.info("Minted #{eip4regs.name}")

            Bobo.Repo.get_by(Bobo.Mint, id: scrollId)
            |> Bobo.Mint.changeset(%{
              :burn_tx => txId,
            })
            |> Bobo.Repo.update()

            Bobo.Repo.get_by(Bobo.Mint, id: id1)
            |> Bobo.Mint.changeset(%{
              :last_use => dbnow(),
              :breed_in_progress => false,
              :release_tx => txId,
            })
            |> Bobo.Repo.update()

            Bobo.Repo.get_by(Bobo.Mint, id: id2)
            |> Bobo.Mint.changeset(%{
              :last_use => dbnow(),
              :breed_in_progress => false,
              :release_tx => txId,
            })
            |> Bobo.Repo.update()

            {:ok, new_creature} =
            Bobo.Mint.changeset(%Bobo.Mint{}, %{
              :id => calculate_bred_creature_id(scrollId, meta.project),
              :name => meta.name,
              :ipfs => meta.ipfs,
              :mint_tx => txId,
              :payment_box_id => Map.get(scrollBox, "boxId"),
              :receiver_address => receiverScroll,
              :is_creature => true,
              :token_id => Map.get(scrollBox, "boxId"),
              :from_ritual_id => scrollId,
              :cd_minutes => meta.cd_minutes,
              :gen => meta.gen,
              :parents => meta.parents,
              :project => meta.project,
            })
            |> Bobo.Repo.insert()

            Bobo.Repo.insert_all(
              Bobo.CreatureFragment,
              Enum.map(meta.fragments, fn f -> %{:creature_id => new_creature.id, :fragment_id => f, :inserted_at => dbnow(), :updated_at => dbnow()} end)
            )

            Ecto.Adapters.SQL.query(Bobo.Repo, "update slots set done=true where scroll_id=#{scrollId};")

            BoboWeb.Endpoint.broadcast("room:lobby", "stats", %{
                :stats => get_mint_stats(),
            })
            BoboWeb.Endpoint.broadcast("room:lobby", "mint", %{
              :name => eip4regs.name,
              :ipfs => eip4regs.url,
              :address => receiverScroll
            })
            BoboWeb.Endpoint.broadcast("room:lobby", "token", %{:token => Map.take(new_creature, @mint_attrlist) |> Jason.encode!} )

            BoboWeb.Endpoint.broadcast("room:lobby", "all_tokens", %{:tokens => get_all_tokens()} )

          else
            cancel_breed_in_progress(id1, id2)
          end
        else
          cancel_breed_in_progress(id1, id2)
        end
      _ ->
        Logger.error("failed to create mint creature tx #{encoded}")
        cancel_breed_in_progress(id1, id2)
    end
  end

  def mint_creature_and_burn_scroll_deprecated(scrollId, id1, id2, scroll_token_id, token_1_id, token_2_id, meta, box, address) do

    eip4regs = %{
      name: meta.name,
      description: "{\"721\":{\"#{meta.name}\": {\"Name\": \"#{meta.name}\",\"Gen\": #{meta.gen}}}}",
      url: meta.ipfs,
      sha256: meta.sha256
    }

    height = get_height()

    txMeta = %{
      :scrollTokenId => scroll_token_id,
      :token1Id => token_1_id,
      :token2Id => token_2_id,
      :recipientAddress => address,
      :changeAddress => @change_address,
      :outputValue => "1000000",
      :txFee => "1110000",
      :height => height,
      :eip4Regs => eip4regs,
      :inputBox => box
    }

    {:ok, encoded} = Jason.encode(txMeta)
    signResponse = System.cmd("node", ["#{@js_scripts_home}mintCreatureUnsignedTx.js", encoded])
    case signResponse do
      {unsigned_tx_string, 0} ->
        {:ok, unsigned_tx} = Jason.decode(unsigned_tx_string)
        Logger.info("unsigned tx #{unsigned_tx_string}")

        signedTx = sign_creature_mint_tx(unsigned_tx)

        #  |> send_tx
        if signedTx != nil do
          Logger.info("signed tx #{Jason.encode!(signedTx)}")
          #txId = nil
          txId = send_tx(signedTx)

          if nil != txId do
            Logger.info("Minted #{eip4regs.name}")

            Bobo.Repo.get_by(Bobo.Mint, id: scrollId)
            |> Bobo.Mint.changeset(%{
              :burn_tx => txId,
              #:payment_box_id => Map.get(box, "boxId"),
            })
            |> Bobo.Repo.update()

            Bobo.Repo.get_by(Bobo.Mint, id: id1)
            |> Bobo.Mint.changeset(%{
              :last_use => dbnow(),
              :breed_in_progress => false,
            })
            |> Bobo.Repo.update()

            Bobo.Repo.get_by(Bobo.Mint, id: id2)
            |> Bobo.Mint.changeset(%{
              :last_use => dbnow(),
              :breed_in_progress => false,
            })
            |> Bobo.Repo.update()

            {:ok, new_creature} =
            Bobo.Mint.changeset(%Bobo.Mint{}, %{
              :id => calculate_bred_creature_id(scrollId, meta.project),
              :name => meta.name,
              :ipfs => meta.ipfs,
              :mint_tx => txId,
              :payment_box_id => Map.get(box, "boxId"),
              :receiver_address => txMeta.recipientAddress,
              :is_creature => true,
              :token_id => Map.get(box, "boxId"),
              :from_ritual_id => scrollId,
              :cd_minutes => meta.cd_minutes,
              :gen => meta.gen,
              :parents => meta.parents,
              :project => meta.project,
            })
            |> Bobo.Repo.insert()

            Bobo.Repo.insert_all(
              Bobo.CreatureFragment,
              Enum.map(meta.fragments, fn f -> %{:creature_id => new_creature.id, :fragment_id => f, :inserted_at => dbnow(), :updated_at => dbnow()} end)
            )

            BoboWeb.Endpoint.broadcast("room:lobby", "all_tokens", %{:tokens => get_all_tokens()} )
            BoboWeb.Endpoint.broadcast("room:lobby", "stats", %{
                :stats => get_mint_stats(),
            })
            BoboWeb.Endpoint.broadcast("room:lobby", "mint", %{
              :name => eip4regs.name,
              :ipfs => eip4regs.url,
              :address => address
            })
            BoboWeb.Endpoint.broadcast("room:lobby", "token", %{:token => Map.take(new_creature, @mint_attrlist) |> Jason.encode!} )



          else
            cancel_breed_in_progress(id1, id2)
          end
        else
          cancel_breed_in_progress(id1, id2)
        end
      _ ->
        Logger.error("failed to create mint creature tx #{encoded}")
        cancel_breed_in_progress(id1, id2)
    end
  end

  defp calculate_bred_creature_id(scrollId, project) do
    case project do
      "inferno" -> scrollId + 1000
      "wooden" -> scrollId + 1000
      "bitmasks" -> scrollId + 1000000
      _ -> nil
    end
  end

  def mintnft(box, eip4regs) do
    address = get_box_sender_address(box)

    if nil == address do
      handleSignTx400Error(box)
    else
      mint_nft_with_address(box, eip4regs, address)
    end
  end

  def mint_nft_with_address(box, eip4regs, address) do
    height = get_height()

    txMeta = %{
      :recipientAddress => address,
      :changeAddress => @change_address,
      :outputValue => "1000000",
      :txFee => "1110000",
      :height => height,
      :eip4Regs => eip4regs,
      :inputBox => box
    }

    {:ok, encoded} = Jason.encode(txMeta)

    signResponse = System.cmd("node", ["#{@js_scripts_home}unsignedTx.js", encoded])
    case signResponse do
      {unsigned_tx_string, 0} ->
        Logger.info("unsigned tx #{unsigned_tx_string}")
        {:ok, unsigned_tx} = Jason.decode(unsigned_tx_string)

        signedTx = sign_tx(unsigned_tx, box)
        #  |> send_tx
        if signedTx != nil do
          #Logger.info("signed tx #{Jason.encode!(signedTx)}")
          #txId = nil
          txId = send_tx(signedTx)

          if nil != txId do
            mint = Bobo.Repo.get_by(Bobo.Mint, payment_box_id: Map.get(box,"boxId"))
            Bobo.Mint.changeset(mint, %{
              :mint_tx => txId,
              :token_id => Map.get(box,"boxId"),
              :receiver_address => address,
            })
            |> Bobo.Repo.update()

            Logger.info("Minted #{eip4regs.name}")

            BoboWeb.Endpoint.broadcast("room:lobby", "stats", %{
                :stats => get_mint_stats(),
            })
            BoboWeb.Endpoint.broadcast("room:lobby", "mint", %{
              :name => eip4regs.name,
              :ipfs => eip4regs.url,
              :address => address
            })

            BoboWeb.Endpoint.broadcast("room:lobby", "all_tokens", %{:tokens => get_all_tokens()} )
          else
            handleSignTx400Error(box)
          end
        end
      _ ->
        Logger.error("failed to sign #{encoded}")
        handleSignTx400Error(box)
    end
  end

  def get_box_sender_address(box) do
    get_tx(Map.get(box, "transactionId"))
    |> get_address_of_first_input_box
  end

  def get_address_of_first_input_box(tx) do
    if tx == :error || tx == nil do
      nil
    else
      Map.get(tx, "inputs")
      |> Enum.at(0)
      |> Map.get("address")
    end
  end

  def get_tx(txId) do
    get_unconfirmed_tx(txId)
  end

  def get_unconfirmed_tx(txId) do
    response =
      SimpleHttp.get("https://api.ergoplatform.com/transactions/unconfirmed/" <> txId,
        headers: %{
          "Content-Type" => "application/json"
        }
      )

    case response do
      {:ok, %{:body => body, :status => 200}} ->
        Jason.decode!(body)

      {:ok, %{:status => 404, :body => body}} ->
        Logger.info("get_unconfirmed_tx: #{inspect(body)}")
        get_confirmed_tx(txId)
      res ->
        Logger.error("get_unconfirmed_tx: #{inspect(res)}")
    end
  end

  def get_confirmed_tx(txId) do
    response =
      SimpleHttp.get("https://api.ergoplatform.com/api/v1/transactions/" <> txId,
        headers: %{
          "Content-Type" => "application/json"
        }
      )

    case response do
      {:ok, %{:body => body, :status => 200}} ->
        Jason.decode!(body)

      {:ok, %{:status => 404, :body => body}} ->
        Logger.info("get_confirmed_tx: #{inspect(body)}")
        :error
      res ->
        Logger.error("get_confirmed_tx: #{inspect(res)}")
    end
  end

  def get_height() do
    {:ok, %{:body => body, :status => 200}} =
      SimpleHttp.get(@node_url <> "/info",
        headers: %{
          "Content-Type" => "application/json"
        }
      )

    Jason.decode!(body)
    |> Map.get("fullHeight")
  end

  def sign_creature_mint_tx(tx) do
    response = SimpleHttp.post(
        @node_url <> "/wallet/transaction/sign",
        body: Jason.encode!(tx),
        headers: %{
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "api_key" => @node_api_key
        },
        timeout: 1000,
        connect_timeout: 1000
      )

    case response do
      {:ok, %{:body => body, :status => 200}} ->
        Jason.decode!(body)
      {:ok, %{:body => body, :status => 400}} ->
        Logger.warn("sign_creature_mint_tx failed #{body}")
        Logger.warn("sign_creature_mint_tx failed #{body}")
        nil
    end
  end

  def sign_tx(tx, box) do
    response = SimpleHttp.post(
        @node_url <> "/wallet/transaction/sign",
        body: Jason.encode!(tx),
        headers: %{
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "api_key" => @node_api_key
        },
        timeout: 1000,
        connect_timeout: 1000
      )

    case response do
      {:ok, %{:body => body, :status => 200}} ->
        Jason.decode!(body)
      {:ok, %{:status => 400}} ->
        handleSignTx400Error(box)
        nil
    end
    # |> Map.get("fullHeight")
  end

  # this gets only called if sign tx returned a 400 -> probably not enough boxes to spend
  def handleSignTx400Error(box) do
    boxId = Map.get(box,"boxId")
    allmints = Bobo.Repo.all(Bobo.Mint, payment_box_id: boxId)
    Enum.each(allmints, fn mint ->
      if mint.mint_tx == nil do
        Bobo.Mint.changeset(mint, %{
          :payment_box_id => nil,
          :payment_tx => nil,
          :confirmations => nil,
        })
        |> Bobo.Repo.update()

        allnftboxes = Bobo.Repo.all(Bobo.Nftbox, box_id: boxId)
        if allnftboxes.length < 0 do
          Enum.each(allnftboxes, fn nftbox ->

              Bobo.Repo.delete nftbox
          end)
        end
      end
    end)
    BoboWeb.Endpoint.broadcast("room:lobby", "stats", %{
      :stats => get_mint_stats(),
    })
  end

  def send_tx(tx) do
    response =
      SimpleHttp.post(
        @node_url <> "/transactions",
        body: Jason.encode!(tx),
        headers: %{
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "api_key" => @node_api_key
        },
        timeout: 1000,
        connect_timeout: 1000
      )

    case response do
      {:ok, %{:body => body, :status => 200}} ->
        Jason.decode!(body)
      _ -> nil
    end
  end

  def fetch_all_wallet_boxes() do
    {:ok, %{:body => body, :status => 200}} =
      SimpleHttp.get(@node_url <> "/wallet/boxes/unspent?minConfirmations=-1&maxConfirmations=-1&minInclusionHeight=0&maxInclusionHeight=-1",
        headers: %{
          "Content-Type" => "application/json",
          "api_key" => @node_api_key
        }
      )
    Jason.decode!(body) |> Enum.map(fn x -> Map.get(x,"box")end)
  end

  ## db stuff
  def get_mint_stats() do
    query =
      "select mint_price_in_nano_erg, count(name) from mints where mint_price_in_nano_erg > 1000000000 and payment_box_id is null  group by mint_price_in_nano_erg;"
    {:ok, %{:rows => rows}} = Ecto.Adapters.SQL.query(Bobo.Repo, query)
    rows
  end

  def get_recent_mints() do
    query =
      "select inserted_at, name, receiver_address, mint_tx, id, is_creature, is_scroll, project  from mints where mint_tx is not null order by inserted_at desc;"

    {:ok, %{:rows => rows}} = Ecto.Adapters.SQL.query(Bobo.Repo, query)
    rows
  end

  def get_all_tokens() do
    Bobo.Mint
    |> where([m], not is_nil(m.token_id))
    |> Bobo.Repo.all
    |> Enum.map(fn x -> Map.take(x, @mint_attrlist) end)
    |> Jason.encode!
  end

  def get_all_slots() do
    Bobo.Slot
    |> Bobo.Repo.all
    |> Enum.map(fn x -> Map.take(x, @slot_attrlist) end)
    |> Jason.encode!
  end

  def dbnow() do
    NaiveDateTime.utc_now()|> NaiveDateTime.truncate(:second)
  end
end
