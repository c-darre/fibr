class DiscussionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show]

  def show
    @analysis = Analysis.find(params[:analysis_id])
    @chat = @analysis.discussion_chat
    @message = Message.new
    @messages = @chat.messages.where.not(content: [nil, ""]).order(:created_at)
  end
end
