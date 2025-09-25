require "administrate/base_dashboard"

class PerformanceEventDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    allocations: Field::Number,
    context: Field::String.with_options(searchable: false),
    db_duration_ms: Field::Number.with_options(decimals: 2),
    duration_ms: Field::Number.with_options(decimals: 2),
    environment: Field::String,
    occurred_at: Field::DateTime,
    project: Field::BelongsTo,
    release: Field::BelongsTo,
    release_version: Field::String,
    request_id: Field::String,
    request_method: Field::String,
    request_path: Field::String,
    server_name: Field::String,
    sql_queries_count: Field::Number,
    target: Field::String,
    user_id_hash: Field::String,
    view_duration_ms: Field::Number.with_options(decimals: 2),
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
    allocations
    context
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    allocations
    context
    db_duration_ms
    duration_ms
    environment
    occurred_at
    project
    release
    release_version
    request_id
    request_method
    request_path
    server_name
    sql_queries_count
    target
    user_id_hash
    view_duration_ms
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    account
    allocations
    context
    db_duration_ms
    duration_ms
    environment
    occurred_at
    project
    release
    release_version
    request_id
    request_method
    request_path
    server_name
    sql_queries_count
    target
    user_id_hash
    view_duration_ms
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

  # Overwrite this method to customize how performance events are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(performance_event)
  #   "PerformanceEvent ##{performance_event.id}"
  # end
end
