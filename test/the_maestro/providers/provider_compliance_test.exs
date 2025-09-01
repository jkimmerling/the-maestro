defmodule TheMaestro.Providers.ProviderComplianceTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Provider

  defmodule TheMaestro.Providers.TestProvider.All do
    # Test module implementing all functions expected by validate_provider_compliance/1
    def create_session(_opts), do: {:ok, "session"}
    def delete_session(_session_id), do: :ok
    def refresh_tokens(_session_id), do: {:ok, %{}}
    def stream_chat(_session_id, _messages, _opts \\ []), do: {:ok, Stream.cycle([:ok])}
    def list_models(_session_id), do: {:ok, []}
  end

  test "validate_provider_compliance returns :ok when all functions present" do
    assert :ok = Provider.validate_provider_compliance(TheMaestro.Providers.TestProvider.All)
  end

  test "validate_provider_compliance validates operation-specific modules without cross-operation errors" do
    # Streaming module should only require streaming callbacks
    assert :ok = Provider.validate_provider_compliance(TheMaestro.Providers.OpenAI.Streaming)
  end
end
