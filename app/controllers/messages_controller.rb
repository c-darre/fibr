class MessagesController < ApplicationController
  skip_before_action :authenticate_user!

  # def create
  #   @analysis = Analysis.find(params[:analysis_id])
  #   chat = @analysis.chat #adapt

  #   message = chat.messages.build(role: :user)
  #   message.photos.attach(message_params[:photos]) if message_params[:photos].present?
  #   message.save!
  #   @analysis.processing!
  #   AnalyzeGarmentJob.perform_later(@analysis.id)

  #   redirect_to analysis_path(@analysis)
  # end

  def create
    @chat = Chat.find(params[:chat_id])
    @analysis = @chat.analysis
    message  = @chat.messages.build(role: :user)

    case @chat.kind
    when "analysis"
      message.photos.attach(message_params[:photos])
      message.save!
      @analysis.processing!
      AnalyzeGarmentJob.perform_later(@analysis.id)
    when "discussion"
      message.content = message_params[:content]
      message.save!
      DiscussionJob.perform_later(@chat.id)
      redirect_to analysis_discussion_path(@analysis) and return
    when "questionnary"
    end

    redirect_to analysis_path(@analysis)
  end

  private

  def message_params
    params.require(:message).permit(:content, photos: [])
  end
end
