defmodule TheMaestro.TUI.MenuHelpers do
  @moduledoc """
  Common utilities for TUI menu interfaces.

  This module provides reusable functions for creating consistent menu interfaces
  in the terminal, including input validation, screen management, and formatting.
  """

  @doc """
  Clears the screen and positions cursor at home.
  """
  @spec clear_screen() :: :ok
  def clear_screen do
    IO.write([IO.ANSI.clear(), IO.ANSI.home()])
    :ok
  end

  @doc """
  Displays a bordered title section.

  ## Parameters
    - `title`: The title text to display
    - `width`: Optional width of the border (default: 80)

  ## Example
      iex> TheMaestro.TUI.MenuHelpers.display_title("PROVIDER SELECTION")
      :ok
  """
  @spec display_title(String.t(), pos_integer()) :: :ok
  def display_title(title, width \\ 80) do
    top_border = "┌" <> String.duplicate("─", width - 2) <> "┐"
    bottom_border = "└" <> String.duplicate("─", width - 2) <> "┘"
    title_line = "│" <> center_text(title, width - 2) <> "│"

    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), top_border])
    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), title_line])
    IO.puts([IO.ANSI.bright(), IO.ANSI.blue(), bottom_border, IO.ANSI.reset()])
    IO.puts("")
    :ok
  end

  @doc """
  Centers text within a given width.

  ## Parameters
    - `text`: The text to center
    - `width`: The total width to center within

  ## Returns
    Centered text string

  ## Example
      iex> TheMaestro.TUI.MenuHelpers.center_text("Hello", 10)
      "  Hello   "
  """
  @spec center_text(String.t(), pos_integer()) :: String.t()
  def center_text(text, width) do
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

  @doc """
  Displays a numbered menu with options.

  ## Parameters
    - `title`: Menu title
    - `options`: List of option strings
    - `additional_info`: Optional map of option_index -> info_text

  ## Returns
    :ok

  ## Example
      iex> options = ["Claude (Anthropic)", "Gemini (Google)", "ChatGPT (OpenAI)"]
      iex> TheMaestro.TUI.MenuHelpers.display_menu("Select Provider", options)
      :ok
  """
  @spec display_menu(String.t(), [String.t()], %{pos_integer() => String.t()}) :: :ok
  def display_menu(title, options, additional_info \\ %{}) do
    clear_screen()
    display_title(title)

    IO.puts([IO.ANSI.bright(), "Choose from the following options:", IO.ANSI.reset()])
    IO.puts("")

    options
    |> Enum.with_index(1)
    |> Enum.each(fn {option, index} ->
      IO.puts([
        IO.ANSI.bright(),
        IO.ANSI.cyan(),
        "#{index}. ",
        IO.ANSI.reset(),
        IO.ANSI.bright(),
        option,
        IO.ANSI.reset()
      ])

      case Map.get(additional_info, index) do
        nil -> :ok
        info -> IO.puts([IO.ANSI.faint(), "   #{info}", IO.ANSI.reset()])
      end

      IO.puts("")
    end)

    :ok
  end

  @doc """
  Gets user input for menu selection.

  ## Parameters
    - `prompt`: The prompt to display
    - `valid_range`: Range of valid numeric choices

  ## Returns
    - `{:ok, choice}`: Valid choice selected
    - `{:error, :invalid_choice}`: Invalid choice
    - `{:error, :quit}`: User chose to quit

  ## Example
      iex> TheMaestro.TUI.MenuHelpers.get_menu_choice("Enter choice (1-3): ", 1..3)
      {:ok, 2}
  """
  @spec get_menu_choice(String.t(), Range.t()) :: {:ok, pos_integer()} | {:error, atom()}
  def get_menu_choice(prompt, valid_range) do
    IO.puts([IO.ANSI.faint(), prompt, IO.ANSI.reset()])

    case IO.gets("") do
      :eof ->
        {:error, :quit}

      {:error, _reason} ->
        {:error, :quit}

      input when is_binary(input) ->
        case parse_choice(String.trim(input), valid_range) do
          {:ok, choice} -> {:ok, choice}
          :error -> {:error, :invalid_choice}
        end
    end
  rescue
    _ -> {:error, :quit}
  catch
    :exit, _ -> {:error, :quit}
  end

  @doc """
  Displays an error message with retry options.

  ## Parameters
    - `message`: Error message to display
    - `retry_options`: List of retry option strings

  ## Returns
    :ok
  """
  @spec display_error(String.t(), [String.t()]) :: :ok
  def display_error(message, retry_options \\ ["Retry", "Back to previous menu", "Exit"]) do
    IO.puts("")
    IO.puts([IO.ANSI.red(), "⚠ Error: #{message}", IO.ANSI.reset()])
    IO.puts("")
    IO.puts([IO.ANSI.bright(), "Options:", IO.ANSI.reset()])

    retry_options
    |> Enum.with_index(1)
    |> Enum.each(fn {option, index} ->
      IO.puts([IO.ANSI.faint(), "#{index}. #{option}", IO.ANSI.reset()])
    end)

    IO.puts("")
    :ok
  end

  @doc """
  Displays a success message.

  ## Parameters
    - `message`: Success message to display

  ## Returns
    :ok
  """
  @spec display_success(String.t()) :: :ok
  def display_success(message) do
    IO.puts([IO.ANSI.green(), "✓ #{message}", IO.ANSI.reset()])
    :ok
  end

  @doc """
  Displays an informational message.

  ## Parameters
    - `message`: Info message to display

  ## Returns
    :ok
  """
  @spec display_info(String.t()) :: :ok
  def display_info(message) do
    IO.puts([IO.ANSI.yellow(), "ℹ #{message}", IO.ANSI.reset()])
    :ok
  end

  @doc """
  Displays a loading spinner for the given duration.

  ## Parameters
    - `message`: Message to display with spinner
    - `duration_ms`: How long to show spinner (default: 2000ms)

  ## Returns
    :ok
  """
  @spec display_loading(String.t(), pos_integer()) :: :ok
  def display_loading(message, duration_ms \\ 2000) do
    spinner_chars = ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]
    start_time = :erlang.system_time(:millisecond)

    Stream.cycle(spinner_chars)
    |> Stream.with_index()
    |> Stream.take_while(fn {_, _index} ->
      current_time = :erlang.system_time(:millisecond)
      elapsed = current_time - start_time

      if elapsed < duration_ms do
        :timer.sleep(100)
        true
      else
        false
      end
    end)
    |> Stream.each(fn {char, _index} ->
      IO.write(["\r", IO.ANSI.cyan(), char, " ", message, IO.ANSI.reset()])
    end)
    |> Stream.run()

    IO.write(["\r", String.duplicate(" ", String.length(message) + 10), "\r"])
    :ok
  end

  @doc """
  Waits for user to press Enter to continue.

  ## Parameters
    - `prompt`: Optional prompt message

  ## Returns
    :ok
  """
  @spec wait_for_enter(String.t()) :: :ok
  def wait_for_enter(prompt \\ "Press Enter to continue...") do
    IO.puts([IO.ANSI.faint(), prompt, IO.ANSI.reset()])
    IO.gets("")
    :ok
  end

  @doc """
  Gets secure input (masked) from user.

  ## Parameters
    - `prompt`: Prompt to display
    - `mask_char`: Character to use for masking (default: "*")

  ## Returns
    - `{:ok, input}`: User input
    - `{:error, :cancelled}`: User cancelled input

  ## Note
    This is a simplified implementation. In production, you might want to use
    a more sophisticated secure input method.
  """
  @spec get_secure_input(String.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def get_secure_input(prompt, mask_char \\ "*") do
    IO.puts([IO.ANSI.bright(), prompt, IO.ANSI.reset()])
    IO.write("Input: ")

    case get_password_input(mask_char) do
      {:ok, input} -> {:ok, input}
      :error -> {:error, :cancelled}
    end
  end

  # Private helper functions

  defp parse_choice(input, valid_range) do
    case Integer.parse(input) do
      {choice, ""} ->
        if choice in valid_range do
          {:ok, choice}
        else
          :error
        end

      _ ->
        :error
    end
  end

  # Simple password input - masks characters as they're typed
  defp get_password_input(mask_char) do
    # Disable echo and read character by character
    :io.setopts([:binary, {:echo, false}])

    result = read_password_chars("", mask_char)

    # Re-enable echo
    :io.setopts([{:echo, true}])
    IO.puts("")

    result
  end

  defp read_password_chars(acc, mask_char) do
    case IO.getn("", 1) do
      "\n" ->
        {:ok, acc}

      "\r" ->
        {:ok, acc}

      "\d" ->
        # Backspace - remove last character
        if String.length(acc) > 0 do
          new_acc = String.slice(acc, 0, String.length(acc) - 1)
          # Move back, write space, move back
          IO.write(["\b \b"])
          read_password_chars(new_acc, mask_char)
        else
          read_password_chars(acc, mask_char)
        end

      "" ->
        # EOF or Ctrl+C
        :error

      char when byte_size(char) == 1 ->
        IO.write(mask_char)
        read_password_chars(acc <> char, mask_char)

      _other ->
        # Ignore other characters
        read_password_chars(acc, mask_char)
    end
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end
end
