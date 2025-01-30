pub fn p95(x: Vec<Option<i64>>) -> Result<Option<i64>, Box<dyn std::error::Error>> {
	let mut x: Vec<i64> = x.into_iter().filter_map(|x| x).collect();
	  
	if x.is_empty() {
		return Ok(None);
	}  
	
	x.sort_unstable();
	
	let rank = 0.95 * x.len() as f64 - 1.0;
	let lower = rank.floor() as usize;
	let upper = rank.ceil() as usize;

	if lower == upper {
		Ok(Some(x[lower]))
	} else {
		let weight = rank - lower as f64;
		Ok(Some((x[lower] as f64 * (1.0 - weight) + x[upper] as f64 * weight) as i64))
	}
}
