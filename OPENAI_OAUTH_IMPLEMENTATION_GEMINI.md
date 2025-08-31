# ✅ ChatGPT Personal Account API - Final Working Implementation

## 🎯 Overview: Success Achieved

This document outlines the exact, working method for interacting with the internal ChatGPT backend API for personal accounts. After a lengthy process of reverse-engineering through source code analysis and iterative testing, we have achieved a fully functional client capable of sending conversations and parsing the streaming response.

- **Authentication**: ✅ **100% COMPLETE**. The OAuth2 flow and `chatgpt-account-id` extraction are working perfectly.
- **API Interaction**: ✅ **100% COMPLETE**. The correct endpoint, payload structure, and model-specific parameters have been identified and implemented.
- **Streaming Response**: ✅ **100% COMPLETE**. The client can now handle the Server-Sent Events (SSE) stream and extract the final text response.

---

## 🔬 The Correct API Interaction Model

Previous attempts failed due to incorrect assumptions. The following is the confirmed, working model.

### 1. Endpoint & Method
- **Method**: `POST`
- **URL**: `https://chatgpt.com/backend-api/codex/responses`

### 2. Required HTTP Headers
- `Authorization`: `Bearer <access_token>`
- `chatgpt-account-id`: `<account_id_from_jwt>`
- `Content-Type`: `application/json`
- `OpenAI-Beta`: `responses=experimental`
- `User-Agent`: A browser-like user agent string.

### 3. The `ResponsesApiRequest` Payload

The API requires a complex JSON object that precisely mirrors internal structures from the `codex` source code. The key discoveries were the `serde(tag = "type")` requirement, which mandates the `"type"` field on certain objects, and several model-specific parameters.

#### **Complete & Working JSON Payload Structure**
```json
{
  "model": "gpt-5",
  "instructions": "<content of prompt.md>",
  "input": [
    {
      "type": "message",
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "<user_instructions>\n\nWhat is 2+2?\n\n</user_instructions>"
        }
      ]
    }
  ],
  "tools": [],
  "tool_choice": "auto",
  "parallel_tool_calls": true,
  "store": false,
  "stream": true,
  "text": {
    "verbosity": "medium"
  }
}
```

#### **Key Payload Fields Explained:**
- **`model`**: The specific model slug. Our testing confirmed `"gpt-5"` works, while `"gpt-4"` is unsupported.
- **`instructions`**: The full content of the `codex` `prompt.md` file.
- **`input`**: An array of `ResponseItem` objects. Each object **must** have a `"type": "message"` field.
- **`content`**: An array of `ContentItem` objects. Each object **must** have a `"type": "input_text"` field.
- **`<user_instructions>` tags**: The user's message text must be wrapped with these literal tags, including newlines.
- **`store`**: **Must be `false`** for the `gpt-5` model.
- **`stream`**: **Must be `true`** for the `gpt-5` model.
- **`text`**: An object containing a `"verbosity"` key (e.g., `"medium"`), required for the `gpt-5` model.
- **`id` and other `nil` fields**: Optional fields like the message `id` must be **completely omitted** from the JSON payload if they have no value, not sent as `null`.

---

## 🌊 Final Working Elixir Script

The following script represents the culmination of our efforts. It correctly authenticates, constructs the precise payload, and handles the streaming SSE response to print the final answer.

**File: `scripts/test_conversation_sending.exs`**
```elixir
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
            send_test_message(tokens.access_token, account_id, "What is 2 + 2?")
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
    request = Finch.build(:post, url, headers, encoded_payload)

    # Correctly use Finch.stream_while/5 with a reducer function
    initial_acc = "" # The initial buffer is an empty string
    reducer = fn
      {:data, chunk}, buffer ->
        new_buffer = buffer <> chunk
        remaining_buffer = process_sse_buffer(new_buffer)
        {:cont, remaining_buffer}

      {event, _}, buffer when event in [:status, :headers] ->
        {:cont, buffer} # Ignore status and headers
    end

    case Finch.stream_while(request, MyFinch, initial_acc, reducer) do
      {:ok, _} ->
        IO.puts("\n✅ Stream finished.")
      {:error, reason} ->
        IO.puts("\n❌ Stream error: #{inspect(reason)}")
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
            {:ok, %{"type" => "output_item.done", "output_item" => output_item}} ->
              extract_final_answer(output_item)
            {:ok, _other_event} ->
              :ok # Ignore other events
            {:error, _} ->
              :ok # Ignore malformed JSON
          end
      end
    end
  end

  defp extract_final_answer(%{"type" => "message", "content" => content_list}) do
    case Enum.find(content_list, &(&1["type"] == "output_text")) do
      %{"text" => text} ->
        IO.puts("\n\n🎯 FINAL ANSWER: #{text}\n")
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
```