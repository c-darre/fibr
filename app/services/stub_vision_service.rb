# app/services/stub_vision_service.rb
# Fake implementation: returns realistic dummy data instantly, without calling OpenAI.
# Same interface as OpenAiVisionService (call method → Hash) so they're interchangeable.
class StubVisionService
  def initialize(analysis)
    @analysis = analysis
  end

  def call
    sleep 2 # simulates the AI "thinking" so you can see the loading screen

    {
      content: "Simulated analysis: good quality fabric, regular stitching, clean finishing.",
      score: 8,
      criteria: [
        { name: "Material",  detail: "Fabric quality and composition detected during analysis.", score: 8 },
        { name: "Cut",       detail: "Cutting precision and silhouette consistency.",             score: 7 },
        { name: "Finishing", detail: "Quality of seams, hems and construction details.",          score: 9 }
      ]
    }
  end
end
