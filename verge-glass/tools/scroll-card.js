(() => {
  const card = document.getElementById("vg-card");
  if (!card) return "no card";
  card.scrollIntoView({ block: "center" });
  return "ok";
})()
