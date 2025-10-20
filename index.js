// index.js
const express = require("express");
const app = express();
const PORT = process.env.PORT || 8000;

app.get("/", (req, res) => {
  res.send("Hello HNG Stage 1!");
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
