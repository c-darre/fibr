class MessagesController < ApplicationController
  skip_before_action :authenticate_user!

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

      Turbo::StreamsChannel.broadcast_append_to(
        "chat_#{@chat.id}",
        target: "messages-container",
        partial: "messages/typing"
      )

      DiscussionJob.perform_later(@chat.id)
      return head :ok
    when "questionnary"
      message.content = message_params[:content]
      message.save!
      QuestionnaryJob.perform_later(@chat.id)
    end

    if @chat.kind == "questionnary"
      redirect_to questionnary_analysis_path(@analysis)
    else
      redirect_to analysis_path(@analysis)
    end
  end

  private

  def message_params
    params.require(:message).permit(:content, photos: [])
  end
end
