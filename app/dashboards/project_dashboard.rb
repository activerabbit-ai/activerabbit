require "administrate/base_dashboard"

class ProjectDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    active: Field::Boolean,
    alert_notifications: Field::HasMany,
    alert_rules: Field::HasMany,
    api_tokens: Field::HasMany,
    description: Field::Text,
    environment: Field::String,
    events: Field::HasMany,
    health_status: Field::String,
    healthchecks: Field::HasMany,
    issues: Field::HasMany,
    last_event_at: Field::DateTime,
    name: Field::String,
    perf_rollups: Field::HasMany,
    releases: Field::HasMany,
    settings: Field::String.with_options(searchable: false),
    slug: Field::String,
    sql_fingerprints: Field::HasMany,
    tech_stack: Field::String,
    url: Field::String,
    user: Field::BelongsTo,
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
    active
    alert_notifications
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    active
    alert_notifications
    alert_rules
    api_tokens
    description
    environment
    events
    health_status
    healthchecks
    issues
    last_event_at
    name
    perf_rollups
    releases
    settings
    slug
    sql_fingerprints
    tech_stack
    url
    user
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    account
    active
    alert_notifications
    alert_rules
    api_tokens
    description
    environment
    events
    health_status
    healthchecks
    issues
    last_event_at
    name
    perf_rollups
    releases
    settings
    slug
    sql_fingerprints
    tech_stack
    url
    user
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

  # Overwrite this method to customize how projects are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(project)
  #   "Project ##{project.id}"
  # end
end
