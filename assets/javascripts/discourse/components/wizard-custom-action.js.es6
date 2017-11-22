import { default as computed } from 'ember-addons/ember-computed-decorators';

const ACTION_TYPES = [
  { id: 'create_topic', name: 'Create Topic' },
  { id: 'update_profile', name: 'Update Profile' },
  { id: 'send_message', name: 'Send Message' }
];

const PROFILE_FIELDS = [
  'name',
  'email',
  'username',
  'title',
  'date_of_birth',
  'muted_usernames',
  'theme_key',
  'locale',
  'bio_raw',
  'location',
  'website',
  'profile_background',
  'card_background'
];

export default Ember.Component.extend({
  classNames: 'wizard-custom-action',
  types: ACTION_TYPES,
  profileFields: PROFILE_FIELDS,
  createTopic: Ember.computed.equal('action.type', 'create_topic'),
  updateProfile: Ember.computed.equal('action.type', 'update_profile'),
  sendMessage: Ember.computed.equal('action.type', 'send_message'),
  disableId: Ember.computed.not('action.isNew'),

  @computed('currentStepId', 'wizard.save_submissions')
  availableFields(currentStepId, saveSubmissions) {
    const allSteps = this.get('wizard.steps');
    let steps = allSteps;
    let fields = [];

    if (!saveSubmissions) {
      steps = [allSteps.findBy('id', currentStepId)];
    }

    steps.forEach((s) => {
      if (s.fields && s.fields.length > 0) {
        let stepFields = s.fields.map((f) => {
          return Ember.Object.create({
            id: f.id,
            label: `${f.id} (${s.id})`
          });
        });
        fields.push(...stepFields);
      }
    });

    return fields;
  }
});