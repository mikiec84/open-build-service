require 'rails_helper'
# WARNING: If you change tests make sure you uncomment this line
# and start a test backend. Some of the BsRequestAction methods
# require real backend answers for projects/packages.
# CONFIG['global_write_through'] = true

RSpec.describe BsRequestAction, vcr: true do
  let(:user) { create(:confirmed_user, login: 'request_user') }

  context 'encoding of sourcediffs' do
    let(:file_content) { "-{\xA2:\xFA*\xA3q\u0010\xC2X\\\x9D" }
    let(:utf8_encoded_file_content) { file_content.encode('UTF-8', 'binary', invalid: :replace, undef: :replace) }
    let(:project) { user.home_project }
    let(:target_package) do
      create(:package_with_file, name: 'package_encoding_1',
                                 file_content: file_content, project: project)
    end
    let(:source_package) do
      create(:package_with_file, name: 'package_encoding_2',
                                 file_content: 'test', project: project)
    end
    let(:bs_request) { create(:bs_request_with_submit_action, creator: user, target_package: target_package, source_package: source_package) }
    let(:bs_request_action) { bs_request.bs_request_actions.first }

    before do
      allow(User).to receive(:current).and_return(user)
    end

    it { expect(bs_request_action.sourcediff.valid_encoding?).to be(true) }
    it { expect(bs_request_action.sourcediff).to include(utf8_encoded_file_content) }
  end

  context 'uniqueness validation of type' do
    let(:source_prj) { create(:project) }
    let(:source_pkg) { create(:package, project: source_prj) }
    let(:target_prj) { create(:project) }
    let(:target_pkg) { create(:package, project: target_prj) }
    let(:action_attributes) do
      {
        type: 'submit',
        source_package: source_pkg,
        source_project: source_prj,
        target_project: target_prj,
        target_package: target_pkg
      }
    end
    let(:bs_request) { create(:bs_request, action_attributes) }
    let!(:bs_request_action) { bs_request.bs_request_actions.first }

    it { expect(bs_request_action).to be_valid }

    it 'validates uniqueness of type among bs requests, target_project and target_package' do
      duplicated_bs_request_action = build(:bs_request_action, action_attributes.merge(bs_request: bs_request))
      expect(duplicated_bs_request_action).not_to be_valid
      expect(duplicated_bs_request_action.errors.full_messages.to_sentence).to eq('Type has already been taken')
    end

    RSpec.shared_examples 'it skips validation for type' do |type|
      context "type '#{type}'" do
        it 'allows multiple bs request actions' do
          expect(build(:bs_request_action, action_attributes.merge(type: type,
                                                                   person_name: user.login,
                                                                   role: Role.find_by_title!('maintainer'),
                                                                   bs_request: bs_request))).to be_valid
        end
      end
    end

    it_should_behave_like 'it skips validation for type', 'add_role'
    it_should_behave_like 'it skips validation for type', 'maintenance_incident'
  end

  it { is_expected.to belong_to(:bs_request).touch(true) }

  describe '.set_source_and_target_associations' do
    let(:project) { create(:project_with_package, name: 'Apache', package_name: 'apache2') }
    let(:package) { project.packages.first }

    it 'sets target_package_object to package if target_package and target_project parameters provided' do
      action = BsRequestAction.create(target_project: project.name, target_package: package)
      expect(action.target_package_object).to eq(package)
    end

    it 'sets target_project_object to project if target_project parameters provided' do
      action = BsRequestAction.create(target_project: project)
      expect(action.target_project_object).to eq(project)
    end
  end

  describe '#find_action_with_same_target' do
    let(:target_package) { create(:package) }
    let(:target_project) { target_package.project }
    let(:source_package) { create(:package) }
    let(:source_project) { source_package.project }
    let(:bs_request) do
      create(:bs_request_with_submit_action,
             source_package: source_package,
             target_package: target_package)
    end
    let(:bs_request_action) { bs_request.bs_request_actions.first }

    context 'with a non existing bs request' do
      it { expect(bs_request_action.find_action_with_same_target(nil)).to be_nil }
    end

    context 'with no matching action' do
      let(:another_bs_request) { build(:bs_request) }

      it { expect(bs_request_action.find_action_with_same_target(another_bs_request)).to be_nil }
    end

    context 'with matching action' do
      let!(:another_bs_request) do
        create(:bs_request_with_submit_action,
               source_package: source_package,
               target_package: target_package)
      end
      let(:another_bs_request_action) { another_bs_request.bs_request_actions.first }

      it { expect(bs_request_action.find_action_with_same_target(another_bs_request)).to eq(another_bs_request_action) }

      context 'with more than one action' do
        let(:another_target_package) { create(:package) }
        let(:another_target_project) { another_target_package.project }
        let(:another_bs_request) do
          create(:bs_request_with_submit_action,
                 source_package: source_package,
                 target_package: another_target_package)
        end
        let(:another_bs_request_action) do
          create(:bs_request_action_submit,
                 bs_request: another_bs_request,
                 source_package: source_package.name,
                 source_project: source_project.name,
                 target_project: target_project.name,
                 target_package: target_package.name)
        end

        before do
          another_bs_request.bs_request_actions << another_bs_request_action
        end

        it { expect(bs_request_action.find_action_with_same_target(another_bs_request)).to eq(another_bs_request_action) }
      end
    end

    describe '#is_target_maintainer?' do
      context 'without target' do
        let(:action_without_target) { build(:bs_request_action) }

        it 'is false' do
          expect(action_without_target).not_to be_is_target_maintainer(user)
        end
        it 'works on nil' do
          expect(action_without_target).not_to be_is_target_maintainer(nil)
        end
      end

      context 'on home target' do
        let(:another_user) { create(:confirmed_user) }
        let(:bs_request) do
          create(:set_bugowner_request, target_project: user.home_project)
        end
        let(:bs_request_action) { bs_request.bs_request_actions.first }

        it 'is true for user' do
          expect(bs_request_action).to be_is_target_maintainer(user)
        end
        it 'works on nil' do
          expect(bs_request_action).not_to be_is_target_maintainer(nil)
        end
        it 'is false for another user' do
          expect(bs_request_action).not_to be_is_target_maintainer(another_user)
        end
      end
    end
  end
end
