const express = require("express");
const app = express();
const port = 3000;

app.get("/", (req, res) => {
  res.send("<h1>My name is khan</h1>");
});

app.get("/twitter", (req, res) => {
  res.send("<h1>Hi Twitter</h1>");
});

app.get("/login", (req, res) => {
  res.send("<h1>Please Login at MA.TECH</h1>");
});

app.listen(port, () => {
  console.log(`App is Listening on Port ${port}`);
});
