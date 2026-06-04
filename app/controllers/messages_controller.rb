class MessagesController < ApplicationController
  skip_before_action :authenticate_user!

  def create_with_pictures
    @analysis = Analysis.find(params[:analysis_id])
    chat = @analysis.chat

    message = chat.messages.build(role: :user)
    message.photos.attach(message_params[:photos]) if message_params[:photos].present?
    message.save!
    @analysis.processing!
    AnalyzeGarmentJob.perform_later(@analysis.id)

    redirect_to analysis_path(@analysis)
  end

  private

  def message_params
    params.require(:message).permit(photos: [])
  end
end
