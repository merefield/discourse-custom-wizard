# name: discourse-custom-wizard
# about: Create custom wizards
# version: 0.1
# authors: Angus McLeod

register_asset 'stylesheets/wizard_custom_admin.scss'
register_asset 'lib/jquery.timepicker.min.js'
register_asset 'lib/jquery.timepicker.scss'

config = Rails.application.config
config.assets.paths << Rails.root.join('plugins', 'discourse-custom-wizard', 'assets', 'javascripts')
config.assets.paths << Rails.root.join('plugins', 'discourse-custom-wizard', 'assets', 'stylesheets', 'wizard')

if Rails.env.production?
  config.assets.precompile += %w{ wizard-custom.js wizard-plugin.js stylesheets/wizard/wizard_custom.scss }
end

after_initialize do
  UserHistory.actions[:custom_wizard_step] = 1000

  require_dependency 'application_controller'
  module ::CustomWizard
    class Engine < ::Rails::Engine
      engine_name 'custom_wizard'
      isolate_namespace CustomWizard
    end
  end

  CustomWizard::Engine.routes.draw do
    get ':wizard_id' => 'wizard#index'
    put ':wizard_id/skip' => 'wizard#skip'
    get ':wizard_id/steps' => 'wizard#index'
    get ':wizard_id/steps/:step_id' => 'wizard#index'
    put ':wizard_id/steps/:step_id' => 'steps#update'
  end

  require_dependency 'admin_constraint'
  Discourse::Application.routes.append do
    mount ::CustomWizard::Engine, at: 'w'

    scope module: 'custom_wizard', constraints: AdminConstraint.new do
      get 'admin/wizards' => 'admin#index'
      get 'admin/wizards/field-types' => 'admin#field_types'
      get 'admin/wizards/custom' => 'admin#index'
      get 'admin/wizards/custom/new' => 'admin#index'
      get 'admin/wizards/custom/all' => 'admin#custom_wizards'
      get 'admin/wizards/custom/:wizard_id' => 'admin#find_wizard'
      put 'admin/wizards/custom/save' => 'admin#save'
      delete 'admin/wizards/custom/remove' => 'admin#remove'
      get 'admin/wizards/submissions' => 'admin#index'
      get 'admin/wizards/submissions/:wizard_id' => 'admin#submissions'
    end
  end

  load File.expand_path('../jobs/clear_after_time_wizard.rb', __FILE__)
  load File.expand_path('../jobs/set_after_time_wizard.rb', __FILE__)
  load File.expand_path('../lib/builder.rb', __FILE__)
  load File.expand_path('../lib/field.rb', __FILE__)
  load File.expand_path('../lib/step_updater.rb', __FILE__)
  load File.expand_path('../lib/template.rb', __FILE__)
  load File.expand_path('../lib/wizard.rb', __FILE__)
  load File.expand_path('../lib/wizard_edits.rb', __FILE__)
  load File.expand_path('../controllers/wizard.rb', __FILE__)
  load File.expand_path('../controllers/steps.rb', __FILE__)
  load File.expand_path('../controllers/admin.rb', __FILE__)

  ::UsersController.class_eval do
    def wizard_path
      if custom_wizard_redirect = $redis.get('custom_wizard_redirect')
        "#{Discourse.base_url}/w/#{custom_wizard_redirect}"
      else
        "#{Discourse.base_url}/wizard"
      end
    end
  end

  module InvitesControllerCustomWizard
    def path(url)
      if Wizard.user_requires_completion?(@user)
        wizard_path = $redis.get('custom_wizard_redirect')
        unless url === '/'
          PluginStore.set("#{wizard_path.underscore}_submissions", @user.id, [{ redirect_to: url }])
        end
        url = "/w/#{wizard_path}"
      end
      super(url)
    end

    private def post_process_invite(user)
      super(user)
      @user = user
    end
  end

  require_dependency 'invites_controller'
  class ::InvitesController
    prepend InvitesControllerCustomWizard
  end

  class ::ApplicationController
    before_action :redirect_to_wizard_if_required, if: :current_user

    def redirect_to_wizard_if_required
      @wizard_id ||= current_user.custom_fields['redirect_to_wizard']
      if @wizard_id && request.referer !~ /w/ && request.referer !~ /admin/
        redirect_to "/w/#{@wizard_id}"
      end
    end
  end

  add_to_serializer(:current_user, :redirect_to_wizard) { object.custom_fields['redirect_to_wizard'] }

  ## TODO limit this to the first admin
  SiteSerializer.class_eval do
    attributes :complete_custom_wizard

    def include_wizard_required?
      scope.is_admin? && Wizard.user_requires_completion?(scope.user)
    end

    def complete_custom_wizard
      if requires_completion = CustomWizard::Wizard.prompt_completion(scope.user)
        requires_completion.map { |w| { name: w[:name], url: "/w/#{w[:id]}" } }
      end
    end

    def include_complete_custom_wizard?
      complete_custom_wizard.present?
    end
  end
end