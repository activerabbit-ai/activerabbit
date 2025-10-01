// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
// Graph controller is auto-registered via eagerLoadControllersFrom

import OnboardingTechStackController from "controllers/onboarding_tech_stack_controller"
application.register("onboarding-tech-stack", OnboardingTechStackController)
