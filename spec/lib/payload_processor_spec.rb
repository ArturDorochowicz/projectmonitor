require 'spec_helper'

describe PayloadProcessor do
  let(:project) { double(Project).as_null_object }
  let(:payload) { double(Payload).as_null_object }
  let(:status) { double(ProjectStatus).as_null_object }
  let(:project_status_updater) { double }
  let(:processor) { PayloadProcessor.new(project_status_updater: project_status_updater) }

  describe "#process" do
    context "when the payload has processable statuses" do
      before do
        payload.stub(status_is_processable?: true)
        payload.stub(:each_status).and_yield(status)
      end

      it "sets the project as online" do
        project.should_receive(:online=).with(true)
        processor.process_payload(project: project, payload: payload)
      end

      it "initializes a ProjectStatus for every payload status" do
        status = double(ProjectStatus, valid?: true).as_null_object
        project.stub(has_status?: false)
        payload.stub(:each_status).and_yield(status).and_yield(status)

        project_status_updater.should_receive(:update_project).twice

        processor.process_payload(project: project, payload: payload)
      end

      it "add a status to the project if the project does not have a matching status" do
        project.stub(has_status?: false)
        expect(project_status_updater).to receive(:update_project).with(project, status)
        processor.process_payload(project: project, payload: payload)
      end

      it "does not add the status to the project if a matching status exists" do
        project.stub(has_status?: true)
        expect(project_status_updater).not_to receive(:update_project)
        processor.process_payload(project: project, payload: payload)
      end

      context "with an invalid status" do
        let(:project) { create(:project) }
        let(:status) { build(:project_status, success: nil) }
        before {
          status.should be_invalid
        }

        it "does not add the status to the project if it is invalid" do
          expect { processor.process_payload(project: project, payload: payload) }.not_to change(project.statuses, :count)
        end

        it "logs an error to the project if the status is invalid" do
          payload.stub(status_content: "some crazy response")
          processor.process_payload(project: project, payload: payload)

          error_entry = project.payload_log_entries.find { |entry| entry.error_type == "Status Invalid" }
          error_entry.should be_present
          error_entry.error_text.should == <<ERROR
Payload returned an invalid status: #{status.inspect}
  Errors: Success is not included in the list
  Payload: #{payload.inspect}
ERROR
        end
      end
    end

    context "when the payload statuses are not processable" do
      before { payload.stub(status_is_processable?: false) }

      it "skips accessing each status" do
        payload.should_not_receive(:each_status)
        processor.process_payload(project: project, payload: payload)
      end

      it "sets the project as offline" do
        project.should_receive(:online=).with(false)
        processor.process_payload(project: project, payload: payload)
      end
    end

    context "when payload has a processable building_status" do
      before { payload.stub(build_status_is_processable?: true) }

      it "sets the project building status to that of the payload" do
        building = double(Boolean)
        payload.stub(building?: building)

        project.should_receive(:building=).with(building)

        processor.process_payload(project: project, payload: payload)
      end
    end

    context "when the payload build_status is not processable" do
      before { payload.stub(build_status_is_processable?: false) }

      it "sets the project as not building" do
        project.should_receive(:building=).with(false)
        processor.process_payload(project: project, payload: payload)
      end
    end

  end

  describe "parse_url" do
    before do
      payload.stub(:status_is_processable?) { true }
      payload.stub(:parsed_url) { 'http://www.example.com' }
    end

    it "should set the project parsed_url" do
      project.should_receive(:parsed_url=).with('http://www.example.com')
      processor.process_payload(project: project, payload: payload)
    end
  end
end
