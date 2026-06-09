class AnalysesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create, :add_pictures, :show, :questionnary, :start_questionnary]

  def index
    # 1. Start with only the current user's analyses that are explicitly "completed"
    @analyses = current_user.analyses.where(status: "completed")

    # 2. If a search query is present, pull in the chat/messages tables to filter text
    if params[:query].present?
      @analyses = @analyses.joins(analysis_chat: :messages)
                          .where("messages.content ILIKE ?", "%#{params[:query]}%")
                          .distinct
    else
      # Keep things organized with the newest completed scans at the top
      @analyses = @analyses.order(created_at: :desc)
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
