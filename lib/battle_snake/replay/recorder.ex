defmodule BattleSnake.Replay.Recorder.Row do
  require Mnesia.Row

  Mnesia.Row.defrow(
    [:id, :attributes],
    [:id, :attributes])
end

defmodule BattleSnake.Replay.Recorder do
  alias BattleSnake.Replay.Recorder
  alias BattleSnake.GameStateEvent
  alias BattleSnake.Replay.Recorder.Row
  alias BattleSnake.GameServer.PubSub
  use GenServer

  #############
  # Type Defs #
  #############

  @type t :: %Recorder{}

  @attributes [:topic, frames: []]
  defstruct @attributes

  ##############
  # Start Link #
  ##############

  def start_link(args, opts) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  ########
  # Init #
  ########

  def init(topic) do
    send(self(), :subscribe_to_topic)
    new_state = %Recorder{topic: topic}
    {:ok, new_state}
  end

  #########################
  # Handle Info Callbacks #
  #########################

  ######################
  # Subscribe to Topic #
  ######################

  def handle_info(:subscribe_to_topic, state) do
    PubSub.subscribe(state.topic)
    {:noreply, state}
  end

  ####################
  # Game State Event #
  ####################

  @doc """
  Incoming Game State Events are appended to the state's "frames" attributes.

  These events are streamed from BattleSnake.GameServer.PubSub after subscribing
  in handle_info(:subscribe_to_topic, state).

  If the event indicates that the game has ended this gen server
  will enable a timeout call.
  """
  @spec handle_info(GameStateEvent.t, t) :: {:noreply, t} | {:noreply, t, timeout}
  def handle_info(%GameStateEvent{data: frame}, state) do
    new_state = update_in(state.frames, &[frame|&1])
    if frame.done? do
      timeout = 2000
      {:noreply, new_state, timeout}
    else
      {:noreply, new_state}
    end
  end

  ###########
  # Timeout #
  ###########

  @doc """
  Timeout handler, started from handle_info(game_state_event, t).

  Once the timeout has expired write the recording to disk and hibernate the
  recorder.
  """
  def handle_info(:timeout, state) do
    require Logger
    Logger.info("writing replay for #{state.topic}")

    state = update_in(state.frames, &Enum.reverse/1)

    created_at = DateTime.utc_now()
    attributes = [recorder: state, created_at: created_at]
    :ok = %Row{id: state.topic, attributes: attributes}
    |> Row.struct2record
    |> Mnesia.dirty_write

    {:noreply, state, :hibernate}
  end

  def terminate(reason, state) do
    require Logger
    Logger.debug "Recorder terminated with reason #{reason}"
    super(reason, state)
  end

  #####################
  # Private Functions #
  #####################
end
