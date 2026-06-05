class DiscussionsController < ApplicationController
  def show
    @analysis = Analysis.find(params[:analysis_id])
    @chat = @analysis.discussion_chat
    @message = Message.new
    @messages = @chat.messages.where.not(content: [nil, ""]).order(:created_at)
  end
end
