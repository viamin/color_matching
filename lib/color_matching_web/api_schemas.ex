defmodule ColorMatchingWeb.ApiSchemas do
  @moduledoc false

  alias OpenApiSpex.Schema

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

  defmodule ErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ApiErrorResponse",
      type: :object,
      properties: %{errors: %Schema{type: :object, additionalProperties: true}},
      required: [:errors]
    })
  end

  defmodule PrinterProfile do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PrinterProfile",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        printer_make_model: %Schema{type: :string},
        paper_type: %Schema{type: :string},
        ink_type: %Schema{type: :string}
      },
      required: [:id, :printer_make_model, :paper_type, :ink_type]
    })
  end

  defmodule Rgb do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "Rgb", type: :object, properties: %{r: %Schema{type: :integer}, g: %Schema{type: :integer}, b: %Schema{type: :integer}}, required: [:r, :g, :b]})
  end

  defmodule PrinterProfilesResponse do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "PrinterProfilesResponse", type: :object, properties: %{printer_profiles: %Schema{type: :array, items: PrinterProfile}}, required: [:printer_profiles]})
  end

  defmodule PalettesResponse do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "PalettesResponse", type: :object, properties: %{palettes: %Schema{type: :array, items: %Schema{type: :object, properties: %{id: %Schema{type: :integer}, name: %Schema{type: :string}, is_preset: %Schema{type: :boolean}, color_count: %Schema{type: :integer}}, required: [:id, :name, :is_preset, :color_count]}}}, required: [:palettes]})
  end

  defmodule ProfileColorsResponse do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "ProfileColorsResponse", type: :object, properties: %{printer_profile: PrinterProfile, colors: %Schema{type: :array, items: %Schema{type: :object, properties: %{name: %Schema{type: :string}, hex: %Schema{type: :string}, rgb: Rgb, responses: %Schema{type: :object, additionalProperties: true}}, required: [:name, :hex, :responses]}}}, required: [:printer_profile, :colors]})
  end

  defmodule ColorsResponse do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "ColorsResponse", type: :object, properties: %{printer_profile: PrinterProfile, colors: %Schema{type: :array, items: %Schema{type: :object, properties: %{id: %Schema{type: :integer}, name: %Schema{type: :string}, hex: %Schema{type: :string}, rgb: Rgb, palette_id: %Schema{type: :integer}, palette_name: %Schema{type: :string, nullable: true}, sort_order: %Schema{type: :integer}, responses: %Schema{type: :object, additionalProperties: true}}, required: [:id, :name, :hex, :palette_id, :sort_order, :responses]}}}, required: [:printer_profile, :colors]})
  end

  defmodule MetamerPairsResponse do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "MetamerPairsResponse", type: :object, properties: %{printer_profile: PrinterProfile, metamer_pairs: %Schema{type: :array, items: %Schema{type: :object, properties: %{pair_id: %Schema{type: :string}, color_a_hex: %Schema{type: :string}, color_b_hex: %Schema{type: :string}, illuminant: %Schema{type: :string}, classification: %Schema{type: :string}, notes: %Schema{type: :string, nullable: true}, classified_at: %Schema{type: :string, format: :"date-time", nullable: true}}, required: [:pair_id, :color_a_hex, :color_b_hex, :illuminant, :classification]}}}, required: [:printer_profile, :metamer_pairs]})
  end

  defmodule RecentSheetsResponse do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "RecentSheetsResponse", type: :object, properties: %{sheets: %Schema{type: :array, items: %Schema{type: :object, properties: %{sheet_id: %Schema{type: :string}, manifest_url: %Schema{type: :string}, title: %Schema{type: :string, nullable: true}}, required: [:sheet_id, :manifest_url, :title]}}}, required: [:sheets]})
  end

  defmodule CaptureRequest do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "CaptureRequest",
      type: :object,
      properties: %{
        device_model: %Schema{type: :string},
        lens: %Schema{type: :string},
        exposure_duration: %Schema{type: :number, exclusiveMinimum: 0},
        iso: %Schema{type: :integer, exclusiveMinimum: 0},
        focus_lens_position: %Schema{type: :number, minimum: 0},
        white_balance_gains: %Schema{type: :object},
        image_width: %Schema{type: :integer, exclusiveMinimum: 0},
        image_height: %Schema{type: :integer, exclusiveMinimum: 0},
        app_version: %Schema{type: :string},
        timestamp: %Schema{type: :string, format: :"date-time"},
        detected_marker_count: %Schema{type: :integer, minimum: 0},
        blur_score: %Schema{type: :number, minimum: 0},
        rejection_reasons: %Schema{type: :array, items: %Schema{type: :string}},
        metadata: CaptureMetadata,
        quality: %Schema{
          type: :object,
          properties: %{
            detected_marker_count: %Schema{type: :integer, minimum: 0},
            blur_score: %Schema{type: :number, minimum: 0},
            rejections: %Schema{type: :array, items: %Schema{type: :string}}
          }
        }
      },
      anyOf: [
        %Schema{
          required: [:device_model, :lens, :image_width, :image_height, :app_version, :timestamp]
        },
        %Schema{required: [:metadata]}
      ]
    })
  end

  defmodule CaptureMetadata do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CaptureMetadata",
      type: :object,
      properties: %{
        device_model: %Schema{type: :string},
        lens: %Schema{type: :string},
        exposure_duration_seconds: %Schema{type: :number, exclusiveMinimum: 0},
        iso: %Schema{type: :integer, exclusiveMinimum: 0},
        focus_lens_position: %Schema{type: :number, minimum: 0},
        white_balance_gains: %Schema{type: :object},
        image_width: %Schema{type: :integer, exclusiveMinimum: 0},
        image_height: %Schema{type: :integer, exclusiveMinimum: 0},
        app_version: %Schema{type: :string},
        timestamp: %Schema{type: :string, format: :"date-time"}
      },
      required: [:device_model, :lens, :image_width, :image_height, :app_version, :timestamp]
    })
  end

  defmodule CaptureCreatedResponse do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "CaptureCreatedResponse", type: :object, properties: %{capture_id: %Schema{type: :string}}, required: [:capture_id]})
  end

  defmodule MeasurementUploadRequest do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "MeasurementUploadRequest",
      type: :object,
      properties: %{
        measurements: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              patch_id: %Schema{type: :string},
              linear_rgb_median: RgbPayload,
              normalized_linear_rgb_median: RgbPayload
            },
            required: [:patch_id, :linear_rgb_median, :normalized_linear_rgb_median]
          }
        },
        pair_scores: %Schema{type: :array, items: PairScoreRequest}
      }
    })
  end

  defmodule RgbPayload do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RgbPayload",
      description: "An RGB array, an object with r/g/b channels, or a JSON-encoded representation.",
      anyOf: [
        %Schema{type: :array, items: %Schema{type: :number}},
        %Schema{
          type: :object,
          properties: %{
            r: %Schema{type: :number},
            g: %Schema{type: :number},
            b: %Schema{type: :number}
          },
          required: [:r, :g, :b]
        },
        %Schema{type: :string}
      ]
    })
  end

  defmodule PairScoreRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PairScoreRequest",
      type: :object,
      description:
        "A score may be supplied directly, as a compatibility similarity, or as a compatibility distance.",
      properties: %{
        pair_id: %Schema{type: :string},
        algorithm_version: %Schema{type: :string},
        score: %Schema{type: :number},
        similarity: %Schema{type: :number},
        distance: %Schema{type: :number}
      },
      required: [:pair_id, :algorithm_version],
      anyOf: [
        %Schema{required: [:score]},
        %Schema{required: [:similarity]},
        %Schema{required: [:distance]}
      ]
    })
  end

  defmodule MeasurementUploadResponse do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "MeasurementUploadResponse", type: :object, properties: %{capture_id: %Schema{type: :string}, measurement_count: %Schema{type: :integer}, pair_score_count: %Schema{type: :integer}}, required: [:capture_id, :measurement_count, :pair_score_count]})
  end

  defmodule JudgmentUploadRequest do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "JudgmentUploadRequest", type: :object, properties: %{judgments: %Schema{type: :array, items: %Schema{type: :object, properties: %{pair_id: %Schema{type: :string}, judgment: %Schema{type: :string}}, required: [:pair_id, :judgment]}}}, required: [:judgments]})
  end

  defmodule JudgmentUploadResponse do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "JudgmentUploadResponse", type: :object, properties: %{capture_id: %Schema{type: :string}, judgment_count: %Schema{type: :integer}}, required: [:capture_id, :judgment_count]})
  end

  defmodule MeasurementRequest do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "IlluminantMeasurementRequest", type: :object, properties: %{color_id: %Schema{type: :integer}, printer_profile_id: %Schema{type: :integer}, light_source: %Schema{type: :string, enum: ["white", "red", "green", "blue", "lps"]}, brightness: %Schema{type: :number, minimum: 0, maximum: 1}}, required: [:color_id, :printer_profile_id, :light_source, :brightness]})
  end

  defmodule MeasurementResponse do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "IlluminantMeasurementResponse", type: :object, properties: %{data: %Schema{type: :object, additionalProperties: true}}, required: [:data]})
  end

  defmodule BulkMeasurementRequest do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{
      title: "BulkIlluminantMeasurementRequest",
      type: :object,
      description:
        "Shared printer profile and light-source metadata apply to every measurement row.",
      properties: %{
        printer_profile_id: %Schema{type: :integer},
        light_source: %Schema{type: :string, enum: ["white", "red", "green", "blue", "lps"]},
        raw_value: %Schema{type: :number},
        raw_unit: %Schema{type: :string},
        notes: %Schema{type: :string},
        measured_at: %Schema{type: :string, format: :"date-time"},
        measurement_method: %Schema{type: :string},
        measurement_device: %Schema{type: :string},
        test_run_id: %Schema{type: :string},
        measurements: %Schema{type: :array, items: BulkMeasurementRow}
      },
      required: [:printer_profile_id, :light_source, :measurements]
    })
  end

  defmodule BulkMeasurementRow do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "BulkIlluminantMeasurementRow",
      type: :object,
      properties: %{
        color_id: %Schema{type: :integer},
        brightness: %Schema{type: :number, minimum: 0, maximum: 1},
        raw_value: %Schema{type: :number},
        raw_unit: %Schema{type: :string},
        notes: %Schema{type: :string}
      },
      required: [:color_id, :brightness]
    })
  end

  defmodule BulkMeasurementResponse do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "BulkIlluminantMeasurementResponse", type: :object, properties: %{data: %Schema{type: :array, items: %Schema{type: :object, additionalProperties: true}}}, required: [:data]})
  end
end
