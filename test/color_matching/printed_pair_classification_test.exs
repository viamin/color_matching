defmodule ColorMatching.Persistence.PrintedPairClassificationTest do
  use ColorMatching.DataCase, async: true

  alias ColorMatching.Persistence.PrintedPairClassification

  test "publishes the canonical vocabulary" do
    assert PrintedPairClassification.illuminants() == ["lps", "red", "green", "blue"]
    assert PrintedPairClassification.classifications() == [
             "strong_metamer",
             "weak_metamer",
             "contrasting"
           ]
  end

  test "validates illuminants and classifications" do
    changeset =
      PrintedPairClassification.changeset(%PrintedPairClassification{}, %{
        test_sheet_pair_id: 1,
        printer_profile_id: 1,
        illuminant: "white",
        classification: "match",
        active: true
      })

    refute changeset.valid?
    assert %{illuminant: ["is invalid"], classification: ["is invalid"]} = errors_on(changeset)
  end
end
