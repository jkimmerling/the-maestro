defmodule TheMaestro.TUI.CLI do
  @moduledoc """
  Terminal User Interface (TUI) for The Maestro AI agent.

  This module provides a terminal-based interface as an alternative "head" 
  for interacting with the core agent, providing a feature-complete CLI experience.

  Uses pure Elixir with ANSI escape codes for cross-platform Mac/Linux support.
  """

  @doc """
  Main entry point for the escript executable.
  """
  def main(args \\ []) do
    # Set environment variable to prevent Phoenix startup
    System.put_env("RUNNING_AS_ESCRIPT", "true")

    # Parse command line arguments (future enhancement)
    _parsed_args = parse_args(args)

    # Initialize the TUI
    initialize_tui()

    # Start the main loop
    run_tui()
  end

  defp initialize_tui do
    # Clear screen and hide cursor
    IO.write([
      IO.ANSI.clear(),
      IO.ANSI.home(),
      # Hide cursor ANSI escape code
      "\e[?25l"
    ])

    # Set up signal handlers for clean exit
    Process.flag(:trap_exit, true)

    # Install SIGINT (Ctrl-C) handler
    # Use a more compatible approach for signal handling
    parent = self()

    spawn_link(fn ->
      Process.register(self(), :signal_handler)
      signal_handler(parent)
    end)

    # Initial state
    initial_state = %{
      conversation_history: [
        %{type: :system, content: "Welcome to The Maestro TUI!"},
        %{type: :system, content: "Type your message and press Enter to chat with the agent."},
        %{type: :system, content: "Press Ctrl-C or 'q' to exit."}
      ],
      current_input: ""
    }

    # Store state in process dictionary for simple state management
    Process.put(:tui_state, initial_state)
  end

  defp run_tui do
    state = Process.get(:tui_state)

    # Check for shutdown message
    receive do
      :shutdown ->
        cleanup_and_exit()
    after
      0 -> :ok
    end

    # Render the interface
    render_interface(state)

    # Handle input
    case get_input() do
      {:quit} ->
        cleanup_and_exit()

      {:input, text} ->
        new_state = handle_user_input(state, text)
        Process.put(:tui_state, new_state)
        run_tui()

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        cleanup_and_exit()
    end
  end

  defp render_interface(state) do
    # Get terminal dimensions
    {width, height} = get_terminal_size()

    # Clear screen and move to top
    IO.write([IO.ANSI.home()])

    # Render header
    header = "╔" <> String.duplicate("═", width - 2) <> "╗"
    title_line = "║" <> center_text("The Maestro TUI", width - 2) <> "║"
    separator = "╠" <> String.duplicate("═", width - 2) <> "╣"

    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), header])
    IO.puts([IO.ANSI.bright(), IO.ANSI.white(), title_line])
    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), separator, IO.ANSI.reset()])

    # Calculate areas
    # Leave space for header, input, and borders
    conversation_height = height - 8

    # Render conversation history
    IO.puts([IO.ANSI.bright(), "Conversation History:", IO.ANSI.reset()])
    render_conversation_history(state.conversation_history, conversation_height, width)

    # Render input area
    input_separator = "╠" <> String.duplicate("═", width - 2) <> "╣"
    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), input_separator, IO.ANSI.reset()])

    IO.puts([IO.ANSI.bright(), "Input: ", IO.ANSI.reset(), state.current_input])
    IO.puts([IO.ANSI.faint(), "Press Enter to send, Ctrl-C or 'q' to quit", IO.ANSI.reset()])

    # Bottom border
    footer = "╚" <> String.duplicate("═", width - 2) <> "╝"
    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), footer, IO.ANSI.reset()])
  end

  defp render_conversation_history(history, max_lines, width) do
    # Take the most recent messages that fit
    messages =
      history
      |> Enum.take(-max_lines)
      |> Enum.with_index()

    Enum.each(messages, fn {message, _index} ->
      color = message_color(message.type)
      type_str = format_message_type(message.type)
      content = truncate_text(message.content, width - 12)

      IO.puts([color, "[#{type_str}] ", IO.ANSI.reset(), content])
    end)

    # Fill remaining lines with empty space
    used_lines = length(messages)
    remaining_lines = max_lines - used_lines

    Enum.each(1..remaining_lines, fn _ ->
      IO.puts("")
    end)
  end

  defp get_input do
    # Read line from stdin
    case IO.gets("") do
      :eof ->
        {:quit}

      {:error, reason} ->
        {:error, reason}

      line when is_binary(line) ->
        trimmed = String.trim(line)

        case trimmed do
          "q" -> {:quit}
          "" -> {:input, ""}
          text -> {:input, text}
        end
    end
  rescue
    _ -> {:quit}
  catch
    :exit, _ -> {:quit}
  end

  defp handle_user_input(state, "") do
    state
  end

  defp handle_user_input(state, input) do
    new_history =
      state.conversation_history ++
        [
          %{type: :user, content: input},
          %{type: :system, content: "Agent response would appear here..."}
        ]

    %{state | conversation_history: new_history, current_input: ""}
  end

  defp signal_handler(parent) do
    receive do
      {:EXIT, _pid, _reason} ->
        send(parent, :shutdown)

      :shutdown ->
        send(parent, :shutdown)

      _ ->
        signal_handler(parent)
    end
  end

  defp cleanup_and_exit do
    # Show cursor and clear screen
    IO.write([
      # Show cursor ANSI escape code
      "\e[?25h",
      IO.ANSI.clear(),
      IO.ANSI.home()
    ])

    IO.puts([IO.ANSI.green(), "Thank you for using The Maestro TUI!", IO.ANSI.reset()])
    System.halt(0)
  end

  # Helper functions
  defp get_terminal_size do
    # Try to get terminal size, fallback to defaults
    case :io.columns() do
      {:ok, width} ->
        case :io.rows() do
          {:ok, height} -> {width, height}
          _ -> {width, 24}
        end

      _ ->
        {80, 24}
    end
  end

  defp center_text(text, width) do
    text_length = String.length(text)

    if text_length >= width do
      String.slice(text, 0, width)
    else
      padding = (width - text_length) / 2
      left_pad = trunc(padding)
      right_pad = width - text_length - left_pad

      String.duplicate(" ", left_pad) <> text <> String.duplicate(" ", right_pad)
    end
  end

  defp truncate_text(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      text
    end
  end

  defp message_color(:user), do: IO.ANSI.cyan()
  defp message_color(:agent), do: IO.ANSI.green()
  defp message_color(:system), do: IO.ANSI.yellow()
  defp message_color(_), do: IO.ANSI.white()

  defp format_message_type(:user), do: "USER"
  defp format_message_type(:agent), do: "AGENT"
  defp format_message_type(:system), do: "SYSTEM"
  defp format_message_type(type), do: String.upcase(to_string(type))

  defp parse_args(args) do
    # Future enhancement: Implement proper argument parsing for CLI options
    # For now, just return empty options
    _args = args
    %{}
  end
end
