#!/usr/bin/env elixir
# Test Conversation Sending to ChatGPT Backend API with Streaming
# Implements the missing "What is 2+2?" functionality from the implementation plan

defmodule ConversationSendingTest do
  @moduledoc """
  Tests the full streaming conversation flow with the ChatGPT backend API,
  mimicking the exact request structure found in the codex source code.
  """

  def test_conversation_sending do
    IO.puts("🧪 Testing Conversation Sending to ChatGPT Backend API (with Streaming)")
    IO.puts("=" |> String.duplicate(70))

    # Ensure dependencies from mix.exs are started
    Application.ensure_all_started(:finch)
    Application.ensure_all_started(:jason)

    # Start Finch for this process
    {:ok, _pid} = Finch.start_link(name: MyFinch)

    # Get stored OAuth tokens from previous test
    case get_stored_tokens() do
      {:ok, tokens} ->
        case get_account_id_from_token(tokens.id_token) do
          {:ok, account_id} ->
            # Prompt 1: Capital of France
            Process.put(:acc_text, "")
            send_test_message(tokens.access_token, account_id, "What is the capital of France?")
            answer1 = (Process.get(:acc_text) || "") |> String.downcase()
            if String.contains?(answer1, "paris") do
              IO.puts("\n✅ Verified 'Paris' present in answer")
            else
              IO.puts("\n⚠️  'Paris' not detected in answer: #{String.slice(answer1, 0, 120)}...")
            end

            # Prompt 2: FastAPI + Stripe (allow long generation)
            Process.put(:acc_text, "")
            send_test_message(tokens.access_token, account_id, "How would you write a FastAPI application that handles Stripe-based subscriptions?")
          {:error, reason} ->
            IO.puts("❌ Failed to extract account_id: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ No stored tokens found: #{inspect(reason)}")
        IO.puts("   Run: mix run scripts/proper_oauth_test.exs step1")
        IO.puts("   Then: mix run scripts/proper_oauth_test.exs step2")
    end
  end

  defp get_stored_tokens do
    case File.read("/tmp/maestro_oauth_tokens.json") do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            tokens = %{
              access_token: data["access_token"],
              id_token: data["id_token"]
            }
            {:ok, tokens}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_account_id_from_token(id_token) do
    case decode_jwt_payload(id_token) do
      {:ok, payload} ->
        account_id = get_in(payload, ["https://api.openai.com/auth", "chatgpt_account_id"])
        if account_id, do: {:ok, account_id}, else: {:error, "No chatgpt_account_id found"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_jwt_payload(jwt_token) do
    case String.split(jwt_token, ".") do
      [_header, payload, _signature] ->
        try do
          case Base.url_decode64(payload, padding: false) do
            {:ok, payload_json} -> Jason.decode(payload_json)
            :error -> {:error, :invalid_base64_encoding}
          end
        rescue
          ArgumentError -> {:error, :invalid_base64_encoding}
        end
      _ ->
        {:error, :invalid_jwt_format}
    end
  end

  defp send_test_message(access_token, account_id, message) do
    IO.puts("🗨️  Sending message: \"#{message}\"")
    IO.puts("🔑 Using account_id: #{String.slice(account_id, 0, 20)}...")

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"chatgpt-account-id", account_id},
      {"Content-Type", "application/json"},
      {"OpenAI-Beta", "responses=experimental"},
      {"User-Agent", "TheMaestro/1.0 (Conversation Test)"}
    ]

    url = "https://chatgpt.com/backend-api/codex/responses"

    prompt_md_path = "/Users/jasonk/Development/the_maestro/source/codex/codex-rs/core/prompt.md"
    instructions = File.read!(prompt_md_path)

    payload_map = %{
      "model" => "gpt-5",
      "instructions" => instructions,
      "input" => [
        %{
          "type" => "message",
          "role" => "user",
          "content" => [
            %{"type" => "input_text", "text" => "<user_instructions>\n\n#{message}\n\n</user_instructions>"}
          ]
        }
      ],
      "tools" => [],
      "tool_choice" => "auto",
      "parallel_tool_calls" => true,
      "reasoning" => nil,
      "store" => false,
      "stream" => true,
      "include" => [],
      "prompt_cache_key" => nil,
      "text" => %{"verbosity" => "medium"}
    }

    final_payload = deep_filter_nils(payload_map)
    encoded_payload = Jason.encode!(final_payload)

    IO.puts("🌐 Sending streaming POST request to: #{url}")
    IO.puts("💬 Response:\n")
    request = Finch.build(:post, url, headers, encoded_payload)

    # Start thinking spinner in a separate process
    spinner_pid = spawn(fn -> thinking_spinner() end)

    # Correctly use Finch.stream_while/5 with a reducer function
    initial_acc = %{buffer: "", first_content: true, spinner_pid: spinner_pid}
    reducer = fn
      {:data, chunk}, acc ->
        new_buffer = acc.buffer <> chunk
        
        # Stop spinner on first content
        if acc.first_content and String.contains?(chunk, "data:") do
          send(acc.spinner_pid, :stop)
          IO.write("\r" <> String.duplicate(" ", 50) <> "\r") # Clear spinner line
        end
        
        remaining_buffer = process_sse_buffer(new_buffer)
        {:cont, %{acc | buffer: remaining_buffer, first_content: false}}

      {event, _}, acc when event in [:status, :headers] ->
        {:cont, acc} # Ignore status and headers
    end

    case Finch.stream_while(request, MyFinch, initial_acc, reducer, receive_timeout: :infinity) do
      {:ok, final_acc} ->
        # Stop spinner if still running
        send(final_acc.spinner_pid, :stop)
        # CRITICAL: Process the final buffer that might contain the last message
        process_sse_buffer(final_acc.buffer)
        IO.puts("\n✅ Stream finished.")
      {:error, reason, final_acc} ->
        send(final_acc.spinner_pid, :stop)
        IO.puts("\n⚠️ Stream error: #{inspect(reason)}")
        IO.puts("Processing final buffer before exit...")
        process_sse_buffer(final_acc.buffer)
      {:error, reason} ->
        send(spinner_pid, :stop)
        IO.puts("\n❌ Stream error: #{inspect(reason)}")
    end
  end

  # --- Thinking Spinner ---

  defp thinking_spinner do
    spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    thinking_messages = ["Thinking", "Processing", "Analyzing", "Generating"]
    
    thinking_spinner_loop(spinner_chars, thinking_messages, 0, 0)
  end

  defp thinking_spinner_loop(spinner_chars, messages, spinner_idx, message_idx) do
    receive do
      :stop -> 
        IO.write("\r" <> String.duplicate(" ", 50) <> "\r")
        :ok
    after
      100 ->
        spinner = Enum.at(spinner_chars, spinner_idx)
        message = Enum.at(messages, message_idx)
        
        IO.write("\r#{spinner} #{message}...")
        
        new_spinner_idx = rem(spinner_idx + 1, length(spinner_chars))
        new_message_idx = if new_spinner_idx == 0, do: rem(message_idx + 1, length(messages)), else: message_idx
        
        thinking_spinner_loop(spinner_chars, messages, new_spinner_idx, new_message_idx)
    end
  end

  # --- SSE Parsing Logic ---

  defp process_sse_buffer(buffer) do
    parts = String.split(buffer, "\n\n")
    {complete_messages, remaining_buffer} = Enum.split(parts, length(parts) - 1)

    for message <- complete_messages do
      parse_sse_message(message)
    end

    List.first(remaining_buffer) || ""
  end

  defp parse_sse_message(message) do
    data_line =
      message
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, "data: "))

    if data_line do
      json_string = String.trim_leading(data_line, "data: ")

      cond do
        String.contains?(json_string, "[DONE]") ->
          :ok
        true ->
          case Jason.decode(json_string) do
            {:ok, event} ->
              case event["type"] do
                "response.output_item.done" ->
                  if output_item = event["output_item"] do
                    if output_item["type"] == "message" do
                      IO.puts("\n🎯 Final Answer Received!")
                    end
                    extract_final_answer(output_item)
                  end
                "response.output_text.delta" ->
                  if delta = event["delta"] do
                    cond do
                      is_binary(delta) ->
                        IO.write(delta)
                        Process.put(:acc_text, (Process.get(:acc_text) || "") <> delta)
                      is_map(delta) and delta["text"] ->
                        IO.write(delta["text"])
                        Process.put(:acc_text, (Process.get(:acc_text) || "") <> (delta["text"] || ""))
                      true -> :ok
                    end
                  end
                "response.content_part.delta" ->
                  if part = event["part"] do
                    if part["type"] == "output_text" and is_binary(part["text"]) do
                      IO.write(part["text"])
                      Process.put(:acc_text, (Process.get(:acc_text) || "") <> part["text"])
                    end
                  end
                "response.completed" ->
                  IO.puts("\n🏁 Response completed!")
                  if response = event["response"] do
                    IO.puts("📊 Usage: #{inspect(response["usage"])}")
                  end
                _other_type ->
                  # Comment out to reduce noise
                  # IO.puts("📨 Other event: #{inspect(other_type)}")
                  :ok
              end
            {:error, reason} ->
              IO.puts("⚠️  JSON decode error: #{inspect(reason)} for: #{json_string}")
              :ok # Ignore malformed JSON
          end
      end
    end
  end

  defp extract_final_answer(%{"type" => "message", "content" => content_list}) do
    case Enum.find(content_list, &(&1["type"] == "output_text")) do
      %{"text" => _text} ->
        IO.puts("\n📝 Complete Response Available")
      _ ->
        :ok
    end
  end
  defp extract_final_answer(_), do: :ok

  # --- Utility Functions ---

  defp deep_filter_nils(collection) do
    case collection do
      map when is_map(map) ->
        map
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.into(%{}, fn {k, v} -> {k, deep_filter_nils(v)} end)
      list when is_list(list) ->
        Enum.map(list, &deep_filter_nils/1)
      other ->
        other
    end
  end
end

# Run the test
ConversationSendingTest.test_conversation_sending()
