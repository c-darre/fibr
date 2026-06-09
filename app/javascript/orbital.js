// Animation orbitale des critères autour du score + clic pour figer/voir le détail
document.addEventListener("DOMContentLoaded", function () {
  const orbital = document.getElementById("orbital")
  if (!orbital) return   // pas sur cette page

  const noeuds = Array.from(document.querySelectorAll(".orbital-node"))
  const total = noeuds.length
  const rayon = 130          // distance des nœuds au centre (px)
  let angle = 0              // angle de rotation courant
  let enRotation = true      // false quand un nœud est sélectionné
  let noeudActif = null

  const detail = document.getElementById("orbital-detail")

  // Place chaque nœud sur le cercle selon l'angle courant
  function placerNoeuds() {
    noeuds.forEach(function (noeud, i) {
      const a = ((i / total) * 360 + angle) * Math.PI / 180
      const x = Math.cos(a) * rayon
      const y = Math.sin(a) * rayon
      noeud.style.transform = "translate(" + x + "px, " + y + "px)"
    })
  }

  // Boucle d'animation (tourne lentement)
  function animer() {
    if (enRotation) {
      angle = (angle + 0.15) % 360
      placerNoeuds()
    }
    requestAnimationFrame(animer)
  }

  // Affiche la carte de détail d'un critère
  function ouvrirDetail(noeud) {
    document.getElementById("detail-name").textContent  = noeud.dataset.name
    document.getElementById("detail-score").textContent = noeud.dataset.score + " / 10"
    document.getElementById("detail-text").textContent  = noeud.dataset.detail
    detail.classList.add("is-open")
  }

  // Clic sur un nœud : on fige la rotation et on montre le détail
  noeuds.forEach(function (noeud) {
    noeud.addEventListener("click", function () {
      if (noeudActif) noeudActif.classList.remove("is-active")
      noeud.classList.add("is-active")
      noeudActif = noeud
      enRotation = false
      ouvrirDetail(noeud)
    })
  })

  // Bouton fermer : on relance la rotation
  document.getElementById("detail-close").addEventListener("click", function () {
    detail.classList.remove("is-open")
    if (noeudActif) noeudActif.classList.remove("is-active")
    noeudActif = null
    enRotation = true
  })

  placerNoeuds()
  animer()
})
