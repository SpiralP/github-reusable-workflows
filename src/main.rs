#[tokio::main]
async fn main() {
    println!("Hello, world!");

    let body = reqwest::get("https://www.github.com/")
        .await
        .unwrap()
        .text()
        .await
        .unwrap();

    println!("{body}");
}
