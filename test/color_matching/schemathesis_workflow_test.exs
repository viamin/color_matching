defmodule ColorMatching.SchemathesisWorkflowTest do
  use ExUnit.Case, async: true

  test "starts the fuzzing server with Phoenix endpoint serving enabled" do
    workflow =
      __DIR__
      |> Path.join("../../.github/workflows/ci.yml")
      |> Path.expand()
      |> File.read!()

    assert workflow =~ "PHX_SERVER: \"true\""
    assert workflow =~ "--url=http://127.0.0.1:4002"
  end
end
