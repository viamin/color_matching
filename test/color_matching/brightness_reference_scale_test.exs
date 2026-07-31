defmodule ColorMatching.BrightnessReferenceScaleTest do
  use ExUnit.Case, async: true

  alias ColorMatching.BrightnessReferenceScale, as: Scale
  alias ColorMatching.Persistence.IlluminantResponse
  alias ColorMatching.PNG

  @expected_gray_values %{
    0 => 0,
    1 => 26,
    2 => 51,
    3 => 77,
    4 => 102,
    5 => 128,
    6 => 153,
    7 => 179,
    8 => 204,
    9 => 230,
    10 => 255
  }

  describe "steps/0" do
    test "has one step per score in the scoring model" do
      steps = Scale.steps()
      scores = Enum.map(steps, & &1.score)

      assert length(steps) == Range.size(IlluminantResponse.score_range())
      assert scores == Enum.to_list(IlluminantResponse.score_range())
    end

    test "labels match the score model and are legible score integers" do
      Scale.steps()
      |> Enum.each(fn step ->
        assert step.label == Integer.to_string(step.score)
        assert step.score in IlluminantResponse.score_range()
      end)
    end

    test "interpolates black-to-white gray values from the score" do
      Scale.steps()
      |> Enum.each(fn step ->
        assert step.gray_value == Map.fetch!(@expected_gray_values, step.score)
      end)
    end

    test "anchors black at the minimum score and white at the maximum score" do
      steps = Scale.steps()

      {min_score, _} = IlluminantResponse.score_range() |> Enum.min_max()

      assert Enum.find(steps, &(&1.score == min_score)).gray_value == 0
      assert Enum.find(steps, &(&1.score == 10)).gray_value == 255
    end

    test "gray values increase monotonically with the score" do
      grays = Scale.steps() |> Enum.map(& &1.gray_value)

      assert grays == Enum.sort(grays)
    end
  end

  describe "new/1" do
    test "binds the scale to a normalized illuminant with the canonical steps" do
      assert {:ok, scale} = Scale.new("  LPS  ")

      assert scale.illuminant == "lps"
      assert scale.steps == Scale.steps()
    end

    test "accepts every supported illuminant" do
      Enum.each(IlluminantResponse.illuminants(), fn illuminant ->
        assert {:ok, %{illuminant: ^illuminant}} = Scale.new(illuminant)
      end)
    end

    test "rejects an unsupported illuminant" do
      assert {:error, "unsupported illuminant: " <> _} = Scale.new("candle")
    end
  end

  describe "description/1" do
    test "describes apparent brightness under the illuminant" do
      assert {:ok, scale} = Scale.new("red")

      assert Scale.description(scale) == "Apparent brightness reference under red light"
    end

    test "never claims swatches appear neutral gray" do
      Enum.each(IlluminantResponse.illuminants(), fn illuminant ->
        {:ok, scale} = Scale.new(illuminant)
        description = Scale.description(scale)

        refute String.contains?(String.downcase(description), "gray")
        refute String.contains?(String.downcase(description), "neutral")
      end)
    end

    test "expands the LPS abbrevation for readability" do
      {:ok, scale} = Scale.new("lps")

      assert Scale.description(scale) ==
               "Apparent brightness reference under low-pressure sodium light"
    end
  end

  describe "to_png/2" do
    test "renders a horizontal strip with one block per step" do
      {:ok, scale} = Scale.new("blue")
      block_size = 8

      assert {:ok, png} = Scale.to_png(scale, block_size: block_size)
      assert {:ok, %{width: width, height: height}} = PNG.inspect_header(png)

      step_count = length(scale.steps)
      assert {width, height} == {step_count * block_size, block_size}
    end

    test "encodes each step block as a uniform gray square" do
      {:ok, scale} = Scale.new("green")
      block_size = 4

      assert {:ok, png} = Scale.to_png(scale, block_size: block_size)
      assert {:ok, %{width: width, pixels: pixels}} = PNG.decode_rgb(png)

      scale.steps
      |> Enum.with_index()
      |> Enum.each(fn {step, index} ->
        x = index * block_size
        pixel = pixel_at(pixels, width, x, 0)

        assert pixel == {step.gray_value, step.gray_value, step.gray_value}
      end)
    end

    test "verifies the full output shape and pixel count" do
      {:ok, scale} = Scale.new("white")

      assert {:ok, png} = Scale.to_png(scale, block_size: 16)
      assert {:ok, %{width: width, height: height}} = PNG.inspect_header(png)

      assert width == 11 * 16
      assert height == 16

      assert {:ok, %{pixels: pixels}} = PNG.decode_rgb(png)
      assert length(pixels) == width * height
    end

    test "renders a vertical strip when requested" do
      {:ok, scale} = Scale.new("red")
      block_size = 10

      assert {:ok, png} = Scale.to_png(scale, block_size: block_size, orientation: :vertical)
      assert {:ok, %{width: width, height: height, pixels: pixels}} = PNG.decode_rgb(png)

      assert {width, height} == {block_size, length(scale.steps) * block_size}
      assert length(pixels) == width * height

      top_pixel = pixel_at(pixels, width, 0, 0)
      bottom_pixel = pixel_at(pixels, width, 0, height - 1)

      assert top_pixel == {0, 0, 0}
      assert bottom_pixel == {255, 255, 255}
    end

    test "is suitable for side-by-side comparison: steps form a smooth black-to-white ramp" do
      {:ok, scale} = Scale.new("lps")

      assert {:ok, png} = Scale.to_png(scale, block_size: 2)
      assert {:ok, %{width: width, pixels: pixels}} = PNG.decode_rgb(png)

      block_grays =
        scale.steps
        |> Enum.with_index()
        |> Enum.map(fn {_step, index} ->
          pixel_at(pixels, width, index * 2, 0) |> elem(0)
        end)

      assert block_grays == Enum.map(scale.steps, & &1.gray_value)
    end

    test "uses the default block size when none is given" do
      {:ok, scale} = Scale.new("white")

      assert {:ok, png} = Scale.to_png(scale)
      assert {:ok, %{width: width, height: height}} = PNG.inspect_header(png)

      assert {width, height} == {11 * 32, 32}
    end

    test "rejects an invalid block size" do
      {:ok, scale} = Scale.new("white")

      assert {:error, "block_size must be a positive integer"} =
               Scale.to_png(scale, block_size: 0)
    end

    test "rejects an unsupported orientation" do
      {:ok, scale} = Scale.new("white")

      assert {:error, "unsupported orientation: " <> _} =
               Scale.to_png(scale, orientation: :diagonal)
    end
  end

  defp pixel_at(pixels, width, x, y) do
    Enum.at(pixels, y * width + x)
  end
end
