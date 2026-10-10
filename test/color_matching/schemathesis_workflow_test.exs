defmodule ColorMatching.SchemathesisWorkflowTest do
  use ExUnit.Case, async: true

  test "starts the fuzzing server with Phoenix endpoint serving enabled" do
    workflow =
      __DIR__
      |> Path.join("../../.github/workflows/ci.yml")
      |> Path.expand()
      |> File.read!()

    assert workflow =~ "PHX_SERVER: \"true\""
  end
end
