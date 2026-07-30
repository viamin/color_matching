defmodule ColorMatching.Persistence.PrintedPairClassificationTest do
  use ColorMatching.DataCase, async: true

  alias ColorMatching.Persistence.PrintedPairClassification

  @valid_attrs %{
    test_sheet_pair_id: 1,
    reproduction_profile_id: 1,
    illuminant: "lps",
    classification: "strong_metamer",
    active: false,
    notes: "Observed under sodium vapor lighting"
  }

  test "publishes the canonical vocabulary" do
    assert PrintedPairClassification.illuminants() == ["lps", "red", "green", "blue"]

    assert PrintedPairClassification.classifications() == [
             "strong_metamer",
             "weak_metamer",
             "contrasting"
           ]
  end

  test "schema defaults active classifications to true" do
    assert %PrintedPairClassification{active: true} = %PrintedPairClassification{}
  end

  test "accepts valid attrs" do
    changeset = PrintedPairClassification.changeset(%PrintedPairClassification{}, @valid_attrs)

    assert changeset.valid?
    assert changeset.changes.notes == @valid_attrs.notes
    assert changeset.changes.active == false
  end

  test "defaults active when attrs omit it" do
    attrs = Map.delete(@valid_attrs, :active)

    changeset = PrintedPairClassification.changeset(%PrintedPairClassification{}, attrs)

    assert changeset.valid?
    assert changeset.data.active == true
    refute Map.has_key?(changeset.changes, :active)
  end

  test "requires identifying fields" do
    changeset = PrintedPairClassification.changeset(%PrintedPairClassification{}, %{})

    refute changeset.valid?

    assert %{
             test_sheet_pair_id: ["can't be blank"],
             reproduction_profile_id: ["can't be blank"],
             illuminant: ["can't be blank"],
             classification: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "validates canonical illuminants and classifications" do
    changeset =
      PrintedPairClassification.changeset(%PrintedPairClassification{}, %{
        @valid_attrs
        | illuminant: "white",
          classification: "match"
      })

    refute changeset.valid?

    assert %{illuminant: ["is invalid"], classification: ["is invalid"]} = errors_on(changeset)
  end
end
