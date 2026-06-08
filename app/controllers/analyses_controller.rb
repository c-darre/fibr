class AnalysesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create, :add_pictures, :show, :questionnary, :start_questionnary]

  def index
    @analyses = current_user.analyses
    if params[:query].present?
      @analyses = @analyses.joins(analysis_chat: :messages).where("messages.content ILIKE ?", "%#{params[:query]}%").distinct
    end
  end


  def create
    @analysis = Analysis.new(user: current_user)
    @analysis.save!
    @analysis.chats.build(kind: :analysis).save
    @analysis.chats.build(kind: :discussion).save
    redirect_to add_pictures_analysis_path(@analysis)
  end

  def add_pictures
    @analysis = Analysis.find(params[:id])
    Message.new(chat: @analysis.analysis_chat)
  end

  def show
    @analysis = Analysis.find(params[:id])
    respond_to do |format|
      format.html
      format.json { render json: { status: @analysis.status } }
    end
  end

  def start_questionnary
    @analysis = Analysis.find(params[:id])
    unless @analysis.questionnary_chat
      chat = @analysis.chats.create!(kind: :questionnary)
      QuestionnaryJob.perform_later(chat.id)
    end
    redirect_to questionnary_analysis_path(@analysis)
  end

  def questionnary
    @analysis = Analysis.find(params[:id])
    @chat = @analysis.questionnary_chat
  end
end
