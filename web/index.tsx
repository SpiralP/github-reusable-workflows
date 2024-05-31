import axios from "axios";

async function main() {
  console.log("Hello, world!");

  const { data } = await axios.get("https://api.github.com/");
  console.log(data);
}

main();
