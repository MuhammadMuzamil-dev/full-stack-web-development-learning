const express = require('express');

const app = express();

const port = 4000;


app.get("/", (req, res ) =>{

res.send("Hello World! This is our first Live Server.")


});



app.listen(port, ()=>{

  console.log(`App is Listening on Port ${port}`)


});


