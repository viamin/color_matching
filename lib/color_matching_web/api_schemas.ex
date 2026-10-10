defmodule ColorMatchingWeb.ApiSchemas do
  @moduledoc false

  alias OpenApiSpex.Schema

  defmodule JsonObject do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "JsonObject",
      type: :object,
      additionalProperties: true
    })
  end

  defmodule Manifest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TestSheetManifest",
      type: :object,
      description: "Versioned sheet manifest consumed by the iOS companion application.",
      properties: %{
        schema_version: %Schema{
          type: :string,
          enum: ["lps-sheet-manifest/v1"],
          description: "Manifest compatibility version."
        },
        sheet_id: %Schema{type: :string},
        capture_profile: %Schema{
          type: :object,
          properties: %{
            scoring_algorithm_version: %Schema{
              type: :string,
              enum: ["lps-distance-v1"],
              description: "Distance-scoring compatibility version."
            }
          },
          required: [:scoring_algorithm_version]
        }
      },
      required: [:schema_version, :sheet_id, :capture_profile]
    })
  end

  defmodule RankedResults do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RankedResults",
      type: :object,
      properties: %{
        schema_version: %Schema{type: :string, enum: ["lps-ranked-results/v1"]},
        sheet_id: %Schema{type: :string}
      },
      required: [:schema_version, :sheet_id]
    })
  end

  defmodule MappingRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MultiImageMappingRequest",
      type: :object,
      required: [:palette_id, :printer_profile_id, :weights, :images],
      properties: %{
        palette_id: %Schema{type: :integer, minimum: 1},
        printer_profile_id: %Schema{type: :integer, minimum: 1},
        weights: %Schema{type: :object, additionalProperties: %Schema{type: :number}},
        images: %Schema{type: :object, additionalProperties: %Schema{type: :string}}
      }
    })
  end
end
