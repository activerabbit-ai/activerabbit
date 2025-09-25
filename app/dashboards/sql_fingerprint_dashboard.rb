require "administrate/base_dashboard"

class SqlFingerprintDashboard < Administrate::BaseDashboard
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
    controller_action: Field::String,
    fingerprint: Field::String,
    first_seen_at: Field::DateTime,
    last_seen_at: Field::DateTime,
    max_duration_ms: Field::Number.with_options(decimals: 2),
    normalized_query: Field::Text,
    project: Field::BelongsTo,
    query_type: Field::String,
    total_count: Field::Number,
    total_duration_ms: Field::Number.with_options(decimals: 2),
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
    controller_action
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    avg_duration_ms
    controller_action
    fingerprint
    first_seen_at
    last_seen_at
    max_duration_ms
    normalized_query
    project
    query_type
    total_count
    total_duration_ms
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    account
    avg_duration_ms
    controller_action
    fingerprint
    first_seen_at
    last_seen_at
    max_duration_ms
    normalized_query
    project
    query_type
    total_count
    total_duration_ms
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

  # Overwrite this method to customize how sql fingerprints are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(sql_fingerprint)
  #   "SqlFingerprint ##{sql_fingerprint.id}"
  # end
end
