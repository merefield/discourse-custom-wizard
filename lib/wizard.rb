require_dependency 'wizard/step'
require_dependency 'wizard/field'
require_dependency 'wizard/step_updater'
require_dependency 'wizard/builder'

class CustomWizard::Wizard

  attr_reader :steps, :user
  attr_accessor :id,
                :name,
                :background,
                :save_submissions,
                :multiple_submissions,
                :after_time,
                :after_signup,
                :required,
                :prompt_completion

  def initialize(user, attrs = {})
    @steps = []
    @user = user
    @first_step = nil

    attrs.each do |key, value|
      setter = "#{key}="
      send(setter, value) if respond_to?(setter.to_sym, false)
    end
  end

  def create_step(step_name)
    ::Wizard::Step.new(step_name)
  end

  def append_step(step)
    step = create_step(step) if step.is_a?(String)

    yield step if block_given?

    last_step = @steps.last

    @steps << step

    # If it's the first step
    if @steps.size == 1
      @first_step = step
      step.index = 0
    elsif last_step.present?
      last_step.next = step
      step.previous = last_step
      step.index = last_step.index + 1
    end
  end

  def start
    if unfinished? && last_completed_step = ::UserHistory.where(
        acting_user_id: @user.id,
        action: ::UserHistory.actions[:custom_wizard_step],
        context: @id,
        subject: @steps.map(&:id)
      ).order("created_at").last

      step_id = last_completed_step.subject
      last_index = @steps.index { |s| s.id == step_id }
      @steps[last_index + 1]
    else
      @first_step
    end
  end

  def create_updater(step_id, fields)
    step = @steps.find { |s| s.id == step_id }
    wizard = self
    CustomWizard::StepUpdater.new(@user, wizard, step, fields)
  end

  def unfinished?
    most_recent = ::UserHistory.where(
      acting_user_id: @user.id,
      action: ::UserHistory.actions[:custom_wizard_step],
      context: @id,
    ).distinct.order('updated_at DESC').first

    if most_recent
      last_finished_step = most_recent.subject
      last_step = CustomWizard::Wizard.step_ids(@id).last
      last_finished_step != last_step
    else
      true
    end
  end

  def completed?
    steps = CustomWizard::Wizard.step_ids(@id)

    history = ::UserHistory.where(
      acting_user_id: @user.id,
      action: ::UserHistory.actions[:custom_wizard_step],
      context: @id
    )

    if @completed_after
      history.where("updated_at > ?", @completed_after)
    end

    completed = history.distinct.order(:subject).pluck(:subject)

    (steps - completed).empty?
  end

  def self.after_signup
    rows = PluginStoreRow.where(plugin_name: 'custom_wizard')
    wizards = [*rows].select { |r| r.value['after_signup'] }
    if wizards.any?
      wizards.first.key
    else
      false
    end
  end

  def self.prompt_completion(user)
    rows = PluginStoreRow.where(plugin_name: 'custom_wizard')
    wizards = [*rows].select { |r| r.value['prompt_completion'] }
    if wizards.any?
      wizards.reduce([]) do |result, w|
        data = ::JSON.parse(w.value)
        id = data['id']
        name = data['name']
        wizard = CustomWizard::Wizard.new(user, id: id, name: name)
        result.push(id: id, name: name) if !wizard.completed?
      end
    else
      false
    end
  end

  def self.steps(wizard_id)
    wizard = PluginStore.get('custom_wizard', wizard_id)
    wizard ? wizard['steps'] : nil
  end

  def self.step_ids(wizard_id)
    steps = self.steps(wizard_id)
    return [] if !steps
    steps.map { |s| s['id'] }.flatten.uniq
  end

  def self.field_ids(wizard_id, step_id)
    steps = self.steps(wizard_id)
    return [] if !steps
    step = steps.select { |s| s['id'] === step_id }.first
    if step && fields = step['fields']
      fields.map { |f| f['id'] }
    else
      []
    end
  end

  def self.add_wizard(json)
    wizard = ::JSON.parse(json)
    PluginStore.set('custom_wizard', wizard["id"], wizard)
  end
end