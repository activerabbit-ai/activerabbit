# Testing Resource Quotas and Usage Tracking

This document describes the RSpec tests for the resource quota and usage tracking features.

## Test Files Created

1. **`spec/models/concerns/resource_quotas_spec.rb`** - Tests for the ResourceQuotas concern
2. **`spec/models/daily_resource_usage_spec.rb`** - Tests for the DailyResourceUsage model
3. **`spec/factories/daily_resource_usages.rb`** - Factory definitions
4. **`spec/requests/pricing_spec.rb`** - Integration tests for the pricing page

## Running the Tests

### Run All Resource Quota Tests

```bash
# Using Docker
docker-compose run --rm web bundle exec rspec spec/models/concerns/resource_quotas_spec.rb

# Locally
bundle exec rspec spec/models/concerns/resource_quotas_spec.rb
```

### Run DailyResourceUsage Tests

```bash
# Using Docker
docker-compose run --rm web bundle exec rspec spec/models/daily_resource_usage_spec.rb

# Locally
bundle exec rspec spec/models/daily_resource_usage_spec.rb
```

### Run Pricing Integration Tests

```bash
# Using Docker
docker-compose run --rm web bundle exec rspec spec/requests/pricing_spec.rb

# Locally
bundle exec rspec spec/requests/pricing_spec.rb
```

### Run All Tests

```bash
# Using Docker
docker-compose run --rm web bundle exec rspec

# Locally
bundle exec rspec
```

### Run Specific Test

```bash
# Run a specific describe block
docker-compose run --rm web bundle exec rspec spec/models/concerns/resource_quotas_spec.rb:45

# Run with specific filter
docker-compose run --rm web bundle exec rspec --tag focus
```

## Test Coverage

### ResourceQuotas Concern (`resource_quotas_spec.rb`)

✅ **PLAN_QUOTAS constant**
- Validates all plans are defined
- Validates all resource types are included

✅ **Quota methods** (for each plan: free, team, business)
- `#event_quota_value` - Returns correct quota for each plan
- `#ai_summaries_quota` - Returns correct quota
- `#pull_requests_quota` - Returns correct quota
- `#uptime_monitors_quota` - Returns correct quota
- `#status_pages_quota` - Returns correct quota
- Handles unknown plans (defaults to free)
- Handles different casing (Free, FREE, free)

✅ **Quota checking**
- `#within_quota?` - Checks if usage is under quota
- Handles at-quota scenarios
- Handles over-quota scenarios
- Returns false for invalid resource types

✅ **Usage percentage**
- `#usage_percentage` - Calculates percentage used
- Handles 0% usage
- Handles over 100% usage
- Handles zero quota gracefully
- Returns 0 for invalid resource types

✅ **Usage summary**
- `#usage_summary` - Returns complete hash with all resources
- Includes quota, used, remaining, percentage, within_quota
- Handles over-quota scenarios

✅ **Billing period helpers**
- Uses custom billing period when set
- Defaults to current month when not set

### DailyResourceUsage Model (`daily_resource_usage_spec.rb`)

✅ **Associations & Validations**
- Belongs to account
- Validates presence of day
- Validates uniqueness of day scoped to account

✅ **`.aggregate_for_account_and_day`**
- Creates new daily usage record
- Aggregates errors count for specific day
- Aggregates AI summaries count
- Aggregates pull requests count
- Aggregates uptime monitors (snapshot)
- Stores nil for zero counts
- Updates existing records
- Works without ActsAsTenant context

✅ **`.usage_for_period`**
- Sums errors across period
- Sums AI summaries across period
- Sums pull requests across period
- Returns max uptime monitors
- Returns max status pages
- Excludes records outside period
- Returns zeros with COALESCE for empty periods
- Handles null values correctly

✅ **`#total_resources_used`**
- Sums all resource counts
- Treats nil as 0
- Returns 0 for all nil values

### Pricing Integration Tests (`pricing_spec.rb`)

✅ **GET /pricing**
- Returns success
- Assigns all instance variables correctly
- Displays current plan for subscribed users
- Displays usage metrics
- Works without subscription
- Shows correct quotas for different plans
- Handles near-quota scenarios
- Handles over-quota scenarios

✅ **Page content**
- Displays all three pricing tiers
- Displays pricing amounts
- Displays feature comparison table
- Displays resource limits

✅ **Authentication**
- Requires user to be signed in
- Redirects to sign in when not authenticated

## Test Data

### Factory Traits

```ruby
# Default factory
create(:daily_resource_usage)

# No usage
create(:daily_resource_usage, :with_no_usage)

# High usage
create(:daily_resource_usage, :with_high_usage)

# Different days
create(:daily_resource_usage, :yesterday)
create(:daily_resource_usage, :last_week)
```

## Common Test Patterns

### Testing with ActsAsTenant

```ruby
ActsAsTenant.with_tenant(account) do
  # Create tenant-scoped records
  create(:event, project: project, account: account)
end

# Or test without tenant context
ActsAsTenant.without_tenant do
  # Direct queries work here
  Event.where(account_id: account.id).count
end
```

### Testing Quota Logic

```ruby
# Set up account with specific plan
account = create(:account, current_plan: "team")

# Stub usage methods
allow(account).to receive(:ai_summaries_used_in_period).and_return(25)

# Test quota checking
expect(account.within_quota?(:ai_summaries)).to be true
expect(account.usage_percentage(:ai_summaries)).to eq(50.0)
```

### Testing Daily Aggregation

```ruby
# Create test data for specific day
day = Date.current
ActsAsTenant.with_tenant(account) do
  create_list(:event, 5, occurred_at: day.to_time)
end

# Aggregate and verify
usage = DailyResourceUsage.aggregate_for_account_and_day(account.id, day)
expect(usage.errors_count).to eq(5)
```

## Debugging Tests

### View Test Output

```bash
# Run with verbose output
docker-compose run --rm web bundle exec rspec --format documentation

# Run with specific seed for reproducibility
docker-compose run --rm web bundle exec rspec --seed 1234
```

### Focus on Failing Tests

```ruby
# Add focus tag to specific test
it "does something", :focus do
  # test code
end

# Run only focused tests
docker-compose run --rm web bundle exec rspec --tag focus
```

### Test Database

```bash
# Reset test database
docker-compose run --rm web bin/rails db:test:prepare

# Check test database schema
docker-compose run --rm web bin/rails db:test:prepare RAILS_ENV=test
```

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Run RSpec tests
  run: |
    docker-compose run --rm web bundle exec rspec spec/models/concerns/resource_quotas_spec.rb
    docker-compose run --rm web bundle exec rspec spec/models/daily_resource_usage_spec.rb
    docker-compose run --rm web bundle exec rspec spec/requests/pricing_spec.rb
```

### GitLab CI Example

```yaml
test:resource_quotas:
  script:
    - docker-compose run --rm web bundle exec rspec spec/models/concerns/resource_quotas_spec.rb
```

## Test Metrics

Expected coverage for these components:
- ResourceQuotas concern: **100%** (all public methods tested)
- DailyResourceUsage model: **95%+** (edge cases covered)
- Pricing controller integration: **90%+** (main flows covered)

## Maintenance

### Adding New Plans

When adding a new plan:
1. Update `PLAN_QUOTAS` in `resource_quotas.rb`
2. Add test case in `resource_quotas_spec.rb`:
   ```ruby
   context "when on new_plan" do
     before { account.current_plan = "new_plan" }

     it "returns correct quota" do
       expect(account.ai_summaries_quota).to eq(75)
     end
   end
   ```

### Adding New Resources

When adding a new resource type:
1. Add to `PLAN_QUOTAS` hash
2. Add quota method in concern
3. Add usage tracking method in concern
4. Update `#usage_summary` to include new resource
5. Add tests for all new methods
6. Update `DailyResourceUsage` if tracking daily usage

## Troubleshooting

### Common Issues

**ActsAsTenant errors:**
```ruby
# Solution: Wrap in ActsAsTenant.without_tenant
ActsAsTenant.without_tenant do
  # queries here
end
```

**Factory not found:**
```bash
# Check if factory is defined
grep -r "factory :daily_resource_usage" spec/factories/
```

**Database not clean between tests:**
```ruby
# Add to spec/rails_helper.rb
config.use_transactional_fixtures = true
```

## Related Documentation

- [PRICING_AND_USAGE_TRACKING_SUMMARY.md](../PRICING_AND_USAGE_TRACKING_SUMMARY.md)
- [RESOURCE_QUOTAS_REFACTORING.md](../RESOURCE_QUOTAS_REFACTORING.md)
- [RSpec Documentation](https://rspec.info/)
- [FactoryBot Documentation](https://github.com/thoughtbot/factory_bot)

