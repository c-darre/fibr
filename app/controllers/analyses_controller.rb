class AnalysesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create, :add_pictures, :show, :questionnary, :start_questionnary, :check_label]

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

  def check_label
    @analysis = Analysis.find(params[:id])

    # Pas de photo envoyée → on ne bloque pas
    photo = params[:photo]
    return render(json: { readable: true }) if photo.blank?

    # En mode stub, on simule "lisible" sans appeler le LLM
    return render(json: { readable: true }) unless ENV["VISION_SERVICE"] == "real"

    readable = label_readable?(photo)
    render json: { readable: readable }
  rescue => e
    Rails.logger.error "check_label failed: #{e.message}"
    # En cas d'erreur, on ne bloque pas l'utilisateur
    render json: { readable: true }
  end


  private

  # Demande au LLM d'extraire la composition. "Lisible" = au moins une fibre trouvée.
  # Demande au LLM d'extraire la composition (même règle que l'analyse complète).
  # "Lisible" = au moins une fibre extraite.
  def label_readable?(photo)
    tmp = Tempfile.new(["fibr_label", File.extname(photo.original_filename.to_s)])
    tmp.binmode
    tmp.write(photo.read)
    tmp.rewind

    chat = RubyLLM.chat(model: "claude-sonnet-4-6")
    chat.with_instructions(
      "You extract the fiber composition from a garment label photo. " \
      "Answer ONLY with valid JSON, no markdown. Format: " \
      "{\"composition\": [{\"fiber\": \"cotton\", \"percentage\": 80}]}. " \
      "If the label lists several layers (OUTER SHELL / INNER SHELL / LINING / PADDING), " \
      "use ONLY the OUTER SHELL composition. The label may repeat info in several languages — " \
      "read the English version. Include a fiber ONLY if you can clearly read its name AND its percentage. " \
      "If the photo is blurry, the label is not visible, or no fiber/percentage can be read, " \
      "return {\"composition\": []}. Never guess."
    )
    response = chat.ask("Extract the outer shell fiber composition from this label.", with: { images: [tmp.path] })

    cleaned = response.content.gsub(/```json|```/, "").strip
    result  = JSON.parse(cleaned)
    composition = result["composition"]
    composition.is_a?(Array) && composition.any?
  ensure
    tmp&.close
    tmp&.unlink
  end

end
