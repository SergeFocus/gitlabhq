require 'spec_helper'

describe MergeRequestsHelper do
  describe 'ci_build_details_path' do
    let(:project) { create(:empty_project) }
    let(:merge_request) { MergeRequest.new }
    let(:ci_service) { CiService.new }
    let(:last_commit) { Ci::Pipeline.new({}) }

    before do
      allow(merge_request).to receive(:source_project).and_return(project)
      allow(merge_request).to receive(:last_commit).and_return(last_commit)
      allow(project).to receive(:ci_service).and_return(ci_service)
      allow(last_commit).to receive(:sha).and_return('12d65c')
    end

    it 'does not include api credentials in a link' do
      allow(ci_service).
        to receive(:build_page).and_return("http://secretuser:secretpass@jenkins.example.com:8888/job/test1/scm/bySHA1/12d65c")
      expect(helper.ci_build_details_path(merge_request)).not_to match("secret")
    end
  end

  describe '#issues_sentence' do
    let(:project) { create :project }

    subject { issues_sentence(issues) }
    let(:issues) do
      [build(:issue, iid: 2, project: project),
       build(:issue, iid: 3, project: project),
       build(:issue, iid: 1, project: project)]
    end

    it do
      @project = project

      is_expected.to eq('#1, #2, and #3')
    end

    context 'for JIRA issues' do
      let(:project) { create(:empty_project) }
      let(:issues) do
        [
          ExternalIssue.new('JIRA-456', project),
          ExternalIssue.new('FOOBAR-7890', project),
          ExternalIssue.new('JIRA-123', project)
        ]
      end

      it do
        @project = project
        is_expected.to eq('FOOBAR-7890, JIRA-123, and JIRA-456')
      end
    end

    context 'for issues from multiple namespaces' do
      let(:project) { create(:project) }
      let(:other_project) { create(:project) }
      let(:issues) do
        [build(:issue, iid: 2, project: project),
         build(:issue, iid: 3, project: other_project),
         build(:issue, iid: 1, project: project)]
      end

      it do
        @project = project

        is_expected.to eq("#1, #2, and #{other_project.namespace.path}/#{other_project.path}#3")
      end
    end
  end

  describe '#format_mr_branch_names' do
    describe 'within the same project' do
      let(:merge_request) { create(:merge_request) }
      subject { format_mr_branch_names(merge_request) }

      it { is_expected.to eq([merge_request.source_branch, merge_request.target_branch]) }
    end

    describe 'within different projects' do
      let(:project) { create(:empty_project) }
      let(:fork_project) { create(:empty_project, forked_from_project: project) }
      let(:merge_request) { create(:merge_request, source_project: fork_project, target_project: project) }
      subject { format_mr_branch_names(merge_request) }
      let(:source_title) { "#{fork_project.path_with_namespace}:#{merge_request.source_branch}" }
      let(:target_title) { "#{project.path_with_namespace}:#{merge_request.target_branch}" }

      it { is_expected.to eq([source_title, target_title]) }
    end
  end

  describe '#mr_widget_refresh_url' do
    let(:guest)         { create(:user) }
    let(:project)       { create(:project, :public) }
    let(:project_fork)  { Projects::ForkService.new(project, guest).execute }
    let(:merge_request) { create(:merge_request, source_project: project_fork, target_project: project) }

    it 'returns correct url for MR' do
      expected_url = "#{project.path_with_namespace}/merge_requests/#{merge_request.iid}/merge_widget_refresh"

      expect(mr_widget_refresh_url(merge_request)).to end_with(expected_url)
    end

    it 'returns empty string for nil' do
      expect(mr_widget_refresh_url(nil)).to eq('')
    end
  end

  describe '#mr_closes_issues' do
    let(:user_1) { create(:user) }
    let(:user_2) { create(:user) }

    let(:project_1) { create(:project, :private, creator: user_1, namespace: user_1.namespace) }
    let(:project_2) { create(:project, :private, creator: user_2, namespace: user_2.namespace) }

    let(:issue_1) { create(:issue, project: project_1) }
    let(:issue_2) { create(:issue, project: project_2) }

    let(:merge_request) { create(:merge_request, source_project: project_1, target_project: project_1,) }

    let(:merge_request) do
      create(:merge_request,
             source_project: project_1, target_project: project_1,
             description: "Fixes #{issue_1.to_reference} Fixes #{issue_2.to_reference(project_1)}")
    end

    before do
      project_1.team << [user_2, :developer]
      project_2.team << [user_2, :developer]
      allow(merge_request.project).to receive(:default_branch).and_return(merge_request.target_branch)
      @merge_request = merge_request
    end

    context 'user without access to another private project' do
      let(:current_user) { user_1 }

      it 'cannot see that project\'s issue that will be closed on acceptance' do
        expect(mr_closes_issues).to contain_exactly(issue_1)
      end
    end

    context 'user with access to another private project' do
      let(:current_user) { user_2 }

      it 'can see that project\'s issue that will be closed on acceptance' do
        expect(mr_closes_issues).to contain_exactly(issue_1, issue_2)
      end
    end
  end

  describe '#target_projects' do
    let(:project) { create(:empty_project) }
    let(:fork_project) { create(:empty_project, forked_from_project: project) }

    context 'when target project has enabled merge requests' do
      it 'returns the forked_from project' do
        expect(target_projects(fork_project)).to contain_exactly(project, fork_project)
      end
    end

    context 'when target project has disabled merge requests' do
      it 'returns the forked project' do
        project.project_feature.update(merge_requests_access_level: 0)

        expect(target_projects(fork_project)).to contain_exactly(fork_project)
      end
    end
  end

  describe '#new_mr_path_from_push_event' do
    subject(:url_params) { URI.decode_www_form(new_mr_path_from_push_event(event)).to_h }
    let(:user) { create(:user) }
    let(:project) { create(:empty_project, creator: user) }
    let(:fork_project) { create(:project, forked_from_project: project, creator: user) }
    let(:event) do
      push_data = Gitlab::DataBuilder::Push.build_sample(fork_project, user)
      create(:event, :pushed, project: fork_project, target: fork_project, author: user, data: push_data)
    end

    context 'when target project has enabled merge requests' do
      it 'returns link to create merge request on source project' do
        expect(url_params['merge_request[target_project_id]'].to_i).to eq(project.id)
      end
    end

    context 'when target project has disabled merge requests' do
      it 'returns link to create merge request on forked project' do
        project.project_feature.update(merge_requests_access_level: 0)

        expect(url_params['merge_request[target_project_id]'].to_i).to eq(fork_project.id)
      end
    end
  end

  describe '#mr_issues_mentioned_but_not_closing' do
    let(:user_1) { create(:user) }
    let(:user_2) { create(:user) }

    let(:project_1) { create(:project, :private, creator: user_1, namespace: user_1.namespace) }
    let(:project_2) { create(:project, :private, creator: user_2, namespace: user_2.namespace) }

    let(:issue_1) { create(:issue, project: project_1) }
    let(:issue_2) { create(:issue, project: project_2) }

    let(:merge_request) do
      create(:merge_request,
             source_project: project_1, target_project: project_1,
             description: "#{issue_1.to_reference} #{issue_2.to_reference(project_1)}")
    end

    before do
      project_1.team << [user_2, :developer]
      project_2.team << [user_2, :developer]
      allow(merge_request.project).to receive(:default_branch).and_return(merge_request.target_branch)
      @merge_request = merge_request
    end

    context 'user without access to another private project' do
      let(:current_user) { user_1 }

      it 'cannot see that project\'s issue that will be closed on acceptance' do
        expect(mr_issues_mentioned_but_not_closing).to contain_exactly(issue_1)
      end
    end

    context 'user with access to another private project' do
      let(:current_user) { user_2 }

      it 'can see that project\'s issue that will be closed on acceptance' do
        expect(mr_issues_mentioned_but_not_closing).to contain_exactly(issue_1, issue_2)
      end
    end
  end

  describe '#render_items_list' do
    it "returns one item in the list" do
      expect(render_items_list(["user"])).to eq("user")
    end

    it "returns two items in the list" do
      expect(render_items_list(%w(user user1))).to eq("user and user1")
    end

    it "returns three items in the list" do
      expect(render_items_list(%w(user user1 user2))).to eq("user, user1 and user2")
    end
  end
end
