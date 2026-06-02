class AnalysesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create, :add_pictures, :show]

  def create
    @analysis = Analysis.new(user: current_user)
    @analysis.save!
    @analysis.create_chat!
    redirect_to add_pictures_analysis_path(@analysis)
  end

  def add_pictures
    @analysis = Analysis.find(params[:id])
    @message = Message.new
  end

  def show
    @analysis = Analysis.find(params[:id])

    respond_to do |format|
      format.html
      format.json { render json: { status: @analysis.status } }
    end
  end
end
