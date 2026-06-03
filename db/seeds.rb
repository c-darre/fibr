# Crée un utilisateur de test
user = User.find_or_create_by!(email: "test@fibr.com") do |u|
  u.password = "password123"
  u.password_confirmation = "password123"
end

Profile.find_or_create_by!(user: user)

# 3 analyses avec des notes différentes
analyses_data = [
  {
    score: 2,
    assistant_message: "Ce vêtement présente de nombreux défauts. Le tissu est de très mauvaise qualité, les coutures lâchent déjà et le coloris est inégal. Note globale : 2/10.",
    criteria: [
      { name: "Qualité du tissu",  detail: "Tissu synthétique très bas de gamme, pelucheux et fragile au toucher.",  score: 1 },
      { name: "Coutures",          detail: "Coutures irrégulières, des fils qui dépassent et une doublure décollée.", score: 2 },
      { name: "Coloris",           detail: "Teinte inégale avec des zones plus claires, déjà décolorées.",            score: 3 },
    ]
  },
  {
    score: 5,
    assistant_message: "Vêtement dans la moyenne. Le tissu est correct et les finitions acceptables, mais sans originalité ni soin particulier. Note globale : 5/10.",
    criteria: [
      { name: "Qualité du tissu",  detail: "Tissu correct, ni exceptionnel ni décevant pour le prix.",             score: 5 },
      { name: "Coutures",          detail: "Coutures propres avec quelques légères irrégularités mineures.",        score: 5 },
      { name: "Coloris",           detail: "Coloris standard, tenue homogène globalement satisfaisante.",           score: 5 },
    ]
  },
  {
    score: 9,
    assistant_message: "Excellent vêtement ! Tissu premium, coupe soignée, finitions impeccables et coloris profond. Une pièce de très haute qualité. Note globale : 9/10.",
    criteria: [
      { name: "Qualité du tissu",  detail: "Laine mérinos premium, toucher doux et excellente tenue dans le temps.", score: 9 },
      { name: "Coutures",          detail: "Coutures parfaitement régulières, aucun défaut visible nulle part.",     score: 10 },
      { name: "Coloris",           detail: "Coloris profond et homogène, teinture haut de gamme très bien fixée.",   score: 9 },
    ]
  }
]

analyses_data.each do |data|
  analysis = Analysis.create!(user: user, score: data[:score], status: :completed)

  chat = Chat.create!(analysis: analysis)

  Message.create!(chat: chat, role: :user,      content: "Voici mon vêtement, peux-tu l'analyser ?")
  Message.create!(chat: chat, role: :assistant, content: data[:assistant_message])

  data[:criteria].each do |c|
    Criterium.create!(analysis: analysis, name: c[:name], detail: c[:detail], score: c[:score])
  end
end

puts "Seed terminé : 3 analyses créées (2/10, 5/10, 9/10) pour #{user.email}"
