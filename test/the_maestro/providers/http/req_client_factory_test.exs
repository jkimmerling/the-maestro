defmodule TheMaestro.Providers.Http.ReqClientFactoryTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Providers.Http.ReqClientFactory

  setup do
    on_exit(fn ->
      # restore provider env to avoid leakage between tests
      Application.delete_env(:the_maestro, :anthropic)
      Application.delete_env(:the_maestro, :openai)
    end)

    :ok
  end

  describe "Anthropic API key client" do
    test "builds Req client with correct base URL, pool, and header order" do
      Application.put_env(:the_maestro, :anthropic, api_key: "sk-test-key")

      assert {:ok, %Req.Request{} = req} = ReqClientFactory.create_client(:anthropic)

      # Verify finch pool and base_url options exist
      assert Map.get(req.options, :finch) == :anthropic_finch
      assert Map.get(req.options, :base_url) == "https://api.anthropic.com"

      # Verify exact header order and values
      expected = %{
        "x-api-key" => ["sk-test-key"],
        "anthropic-version" => ["2023-06-01"],
        "anthropic-beta" => ["messages-2023-12-15"],
        "user-agent" => ["llxprt/1.0"],
        "accept" => ["application/json"],
        "x-client-version" => ["1.0.0"]
      }

      assert req.headers == expected
    end

    test "returns error when API key is missing" do
      Application.put_env(:the_maestro, :anthropic, api_key: nil)
      assert {:error, :missing_api_key} = ReqClientFactory.create_client(:anthropic)
    end
  end

  describe "OpenAI Bearer token client" do
    test "builds Req client with exact header order" do
      api_key = System.get_env("OPENAI_API_KEY") || "sk-openai-test"
      org_id = System.get_env("OPENAI_ORG_ID") || "org-test"
      Application.put_env(:the_maestro, :openai, api_key: api_key, organization_id: org_id)

      assert {:ok, %Req.Request{} = req} = ReqClientFactory.create_client(:openai)
      assert Map.get(req.options, :finch) == :openai_finch
      assert Map.get(req.options, :base_url) == "https://api.openai.com"

      expected = %{
        "authorization" => ["Bearer #{api_key}"],
        "openai-organization" => [org_id],
        "openai-beta" => ["assistants v2"],
        "user-agent" => ["llxprt/1.0"],
        "accept" => ["application/json"],
        "x-client-version" => ["1.0.0"]
      }

      assert req.headers == expected
    end

    test "returns error when API key missing" do
      Application.put_env(:the_maestro, :openai, api_key: nil, organization_id: "org")
      assert {:error, :missing_api_key} = ReqClientFactory.create_client(:openai)
    end

    test "returns error when org id missing" do
      Application.put_env(:the_maestro, :openai, api_key: "sk", organization_id: "")
      assert {:error, :missing_org_id} = ReqClientFactory.create_client(:openai)
    end
  end

  describe "Gemini client" do
    test "builds Req client with base URL and pool, no default headers" do
      assert {:ok, %Req.Request{} = req} = ReqClientFactory.create_client(:gemini)
      assert Map.get(req.options, :finch) == :gemini_finch
      assert Map.get(req.options, :base_url) == "https://generativelanguage.googleapis.com"
      assert req.headers == %{}
    end
  end

  describe "Invalid provider" do
    test "returns error" do
      assert {:error, :invalid_provider} = ReqClientFactory.create_client(:invalid)
    end
  end
end
