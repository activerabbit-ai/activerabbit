require "administrate/base_dashboard"

class AlertRuleDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    alert_notifications: Field::HasMany,
    conditions: Field::String.with_options(searchable: false),
    cooldown_minutes: Field::Number,
    enabled: Field::Boolean,
    name: Field::String,
    project: Field::BelongsTo,
    rule_type: Field::String,
    threshold_value: Field::Number.with_options(decimals: 2),
    time_window_minutes: Field::Number,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    account
    alert_notifications
    conditions
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    alert_notifications
    conditions
    cooldown_minutes
    enabled
    name
    project
    rule_type
    threshold_value
    time_window_minutes
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    account
    alert_notifications
    conditions
    cooldown_minutes
    enabled
    name
    project
    rule_type
    threshold_value
    time_window_minutes
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

  # Overwrite this method to customize how alert rules are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(alert_rule)
  #   "AlertRule ##{alert_rule.id}"
  # end
end
