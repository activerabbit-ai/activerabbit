require "administrate/base_dashboard"

class IssueDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    ai_summary: Field::Text,
    ai_summary_generated_at: Field::DateTime,
    closed_at: Field::DateTime,
    controller_action: Field::String,
    count: Field::Number,
    events: Field::HasMany,
    exception_class: Field::String,
    fingerprint: Field::String,
    first_seen_at: Field::DateTime,
    last_seen_at: Field::DateTime,
    project: Field::BelongsTo,
    sample_message: Field::Text,
    status: Field::String,
    top_frame: Field::Text,
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
    ai_summary
    ai_summary_generated_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    ai_summary
    ai_summary_generated_at
    closed_at
    controller_action
    count
    events
    exception_class
    fingerprint
    first_seen_at
    last_seen_at
    project
    sample_message
    status
    top_frame
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    account
    ai_summary
    ai_summary_generated_at
    closed_at
    controller_action
    count
    events
    exception_class
    fingerprint
    first_seen_at
    last_seen_at
    project
    sample_message
    status
    top_frame
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

  # Overwrite this method to customize how issues are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(issue)
  #   "Issue ##{issue.id}"
  # end
end
