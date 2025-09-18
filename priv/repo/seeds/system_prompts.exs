alias TheMaestro.SystemPrompts.Seeder

case Seeder.seed!() do
  :ok -> IO.puts("[system_prompts] canonical prompts seeded")
  {:error, reason} -> raise "Failed to seed system prompts: #{inspect(reason)}"
end
