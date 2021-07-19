require 'rails_helper'
require 'webmock/rspec'

RSpec.describe SearchController, vcr: true do
  render_views

  let!(:user) { create(:confirmed_user, :with_home, login: 'foo') }

  before do
    login user
  end

  shared_examples 'find project' do
    it { expect(response).to have_http_status(:success) }
    it { expect(Xmlhash.parse(response.body)['project']['name']).to eq(user.home_project.name) }
  end

  shared_examples 'find package' do
    it { expect(response).to have_http_status(:success) }
    it { expect(Xmlhash.parse(response.body)['package']['project']).to eq(user.home_project.name) }
  end

  describe 'search for projects' do
    subject! { get :project, params: { match: "@name='#{user.home_project.name}'" } }

    it_behaves_like 'find project'
  end

  describe 'search for project ids' do
    subject! { get :project_id, params: { match: "@name='#{user.home_project.name}'" } }

    it_behaves_like 'find project'
  end

  describe 'search for packages' do
    let!(:package) { create(:package, name: 'apacheX', project: user.home_project) }

    subject! { get :package, params: { match: "@name='apacheX'" } }

    it_behaves_like 'find package'
  end

  describe 'search for package ids' do
    let!(:package) { create(:package, name: 'apacheX', project: user.home_project) }

    subject! { get :package_id, params: { match: "@name='apacheX'" } }

    it_behaves_like 'find package'
  end
end
