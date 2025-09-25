require "administrate/base_dashboard"

class PerfRollupDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    avg_duration_ms: Field::Number.with_options(decimals: 2),
    environment: Field::String,
    error_count: Field::Number,
    hdr_histogram: Field::String.with_options(searchable: false),
    max_duration_ms: Field::Number.with_options(decimals: 2),
    min_duration_ms: Field::Number.with_options(decimals: 2),
    p50_duration_ms: Field::Number.with_options(decimals: 2),
    p95_duration_ms: Field::Number.with_options(decimals: 2),
    p99_duration_ms: Field::Number.with_options(decimals: 2),
    project: Field::BelongsTo,
    request_count: Field::Number,
    target: Field::String,
    timeframe: Field::String,
    timestamp: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    account
    avg_duration_ms
    environment
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    avg_duration_ms
    environment
    error_count
    hdr_histogram
    max_duration_ms
    min_duration_ms
    p50_duration_ms
    p95_duration_ms
    p99_duration_ms
    project
    request_count
    target
    timeframe
    timestamp
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    account
    avg_duration_ms
    environment
    error_count
    hdr_histogram
    max_duration_ms
    min_duration_ms
    p50_duration_ms
    p95_duration_ms
    p99_duration_ms
    project
    request_count
    target
    timeframe
    timestamp
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how perf rollups are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(perf_rollup)
  #   "PerfRollup ##{perf_rollup.id}"
  # end
end
