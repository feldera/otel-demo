pub fn p95(x: Vec<Option<i64>>) -> Result<Option<i64>, Box<dyn std::error::Error>> {
    let mut x: Vec<i64> = x.into_iter().filter_map(|x| x).collect();
    x.sort_unstable();
    let idx = (0.95 * x.len() as f64).ceil() as usize;
    Ok(x.get(idx).copied())
}
