# frozen_string_literal: true

# Pagy initializer file (9.0+)
# Customize only what you really need and notice that the core Pagy works also without any of the following lines.
# Should you just cherry pick part of this file, please maintain the require-order of the extras

# Pagy DEFAULT Variables
# See https://ddnexus.github.io/pagy/docs/api/pagy#variables
# All the Pagy::DEFAULT are set for all the Pagy instances but can be overridden
# per instance by just passing them to Pagy.new or the #pagy method
# Examples:
# default 20 items per page: Pagy::DEFAULT[:limit] = 20
# pagy instance with 10 items per page: pagy(scope, limit: 10)

# Instance variables (See https://ddnexus.github.io/pagy/docs/api/pagy#instance-variables)
Pagy::DEFAULT[:limit] = 50 # items per page

# Other Variables
# See https://ddnexus.github.io/pagy/docs/api/pagy#other-variables
# Pagy::DEFAULT[:size]       = [1,4,4,1]                       # nav bar links
# Pagy::DEFAULT[:page_param] = :page                           # the page parameter
# Pagy::DEFAULT[:params]     = {}                              # params to add to the request
# Pagy::DEFAULT[:fragment]   = '#fragment'                     # fragment to add to the request
# Pagy::DEFAULT[:link_extra] = 'data-remote="true"'            # extra attributes for page links
# Pagy::DEFAULT[:i18n_key]   = 'pagy.item_name'                # i18n key

# Extras
# See https://ddnexus.github.io/pagy/docs/extras

# Backend Extras

# Array extra: Paginate arrays efficiently, avoiding expensive array-wrapping and without overriding
# See https://ddnexus.github.io/pagy/docs/extras/array
require "pagy/extras/array"

# Countless extra: Paginate without any count, saving one query per rendering
# See https://ddnexus.github.io/pagy/docs/extras/countless
# require 'pagy/extras/countless'

# Metadata extra: Provides the pagination metadata to Javascript frameworks like Vue.js, react.js, etc.
# See https://ddnexus.github.io/pagy/docs/extras/metadata
# require 'pagy/extras/metadata'

# Overflow extra: Allow for easy handling of overflowing pages
# See https://ddnexus.github.io/pagy/docs/extras/overflow
# Pagy::DEFAULT[:overflow] = :empty_page    # default  (other options: :last_page and :exception)

# Support extra: Extra support for features like: incremental, auto-incremental and infinite pagination
# See https://ddnexus.github.io/pagy/docs/extras/support
# require 'pagy/extras/support'

# Frontend Extras

# Bootstrap extra: Nav helper and templates for Bootstrap pagination
# See https://ddnexus.github.io/pagy/docs/extras/bootstrap
# require 'pagy/extras/bootstrap'

# Bulma extra: Nav helper and templates for Bulma pagination
# See https://ddnexus.github.io/pagy/docs/extras/bulma
# require 'pagy/extras/bulma'

# Foundation extra: Nav helper and templates for Foundation pagination
# See https://ddnexus.github.io/pagy/docs/extras/foundation
# require 'pagy/extras/foundation'

# Materialize extra: Nav helper and templates for Materialize pagination
# See https://ddnexus.github.io/pagy/docs/extras/materialize
# require 'pagy/extras/materialize'

# Semantic extra: Nav helper and templates for Semantic UI pagination
# See https://ddnexus.github.io/pagy/docs/extras/semantic
# require 'pagy/extras/semantic'

# UIkit extra: Nav helper and templates for UIkit pagination
# See https://ddnexus.github.io/pagy/docs/extras/uikit
# require 'pagy/extras/uikit'

# Tailwind extra: better integration with Tailwind CSS
# See https://ddnexus.github.io/pagy/docs/extras/tailwind
# require 'pagy/extras/tailwind'

# Multi size var used by the *_nav_js helpers
# See https://ddnexus.github.io/pagy/docs/extras/tailwind#javascript
# Pagy::DEFAULT[:steps] = { 0 => [2,3,3,2], 540 => [3,5,5,3], 720 => [5,7,7,5] }

# Standalone extra: Use pagy in non Rack environment/gem
# See https://ddnexus.github.io/pagy/docs/extras/standalone
# require 'pagy/extras/standalone'
