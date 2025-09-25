require "administrate/base_dashboard"

class EventDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    backtrace: Field::Text,
    context: Field::String.with_options(searchable: false),
    controller_action: Field::String,
    environment: Field::String,
    exception_class: Field::String,
    issue: Field::BelongsTo,
    message: Field::Text,
    occurred_at: Field::DateTime,
    project: Field::BelongsTo,
    release: Field::BelongsTo,
    release_version: Field::String,
    request_id: Field::String,
    request_method: Field::String,
    request_path: Field::String,
    server_name: Field::String,
    user_id_hash: Field::String,
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
    backtrace
    context
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    backtrace
    context
    controller_action
    environment
    exception_class
    issue
    message
    occurred_at
    project
    release
    release_version
    request_id
    request_method
    request_path
    server_name
    user_id_hash
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    account
    backtrace
    context
    controller_action
    environment
    exception_class
    issue
    message
    occurred_at
    project
    release
    release_version
    request_id
    request_method
    request_path
    server_name
    user_id_hash
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

  # Overwrite this method to customize how events are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(event)
  #   "Event ##{event.id}"
  # end
end
