extends RefCounted
## Local first names for filling seats, so a table in Lahore looks like Lahore.

const POOLS := {
	"PK": ["Ayesha", "Hamza", "Fatima", "Bilal", "Zara", "Usman", "Hira", "Ali", "Sana", "Saad", "Mehwish",
		"Danish", "Noor", "Kashif", "Iqra", "Faizan", "Maham", "Hassan", "Areeba", "Talha", "Laiba", "Zain",
		"Rida", "Shahzaib", "Anaya", "Umair", "Komal", "Waleed", "Mahnoor", "Junaid"],
	"IN": ["Aarav", "Diya", "Vivaan", "Ananya", "Arjun", "Isha", "Kabir", "Meera", "Rohan", "Priya", "Aditya",
		"Sneha", "Ishaan", "Kavya", "Rahul", "Pooja", "Vikram", "Nisha", "Karan", "Riya", "Siddharth", "Tara",
		"Aman", "Neha", "Dev", "Simran", "Yash", "Anjali", "Varun", "Kiara"],
	"BD": ["Rafi", "Nusrat", "Tanvir", "Sadia", "Arif", "Farzana", "Imran", "Tania", "Sabbir", "Mim",
		"Rakib", "Jannat", "Shuvo", "Lamia", "Fahim", "Riya", "Nayeem", "Sumaiya"],
	"WORLD": ["Alex", "Maya", "Leo", "Sofia", "Omar", "Lina", "Noah", "Emma", "Yusuf", "Mia", "Lucas",
		"Aisha", "Daniel", "Sara", "Adam", "Elena", "Ryan", "Layla", "Ethan", "Nadia", "Sam", "Chloe"],
}

## Avatar ids the client knows how to draw (art/avatars/<id>.png).
const AVATARS := ["a01", "a02", "a03", "a04", "a05", "a06", "a07", "a08", "a09", "a10", "a11", "a12"]


static func pick(country: String, rng: RandomNumberGenerator, taken: Array) -> String:
	var pool: Array = POOLS.get(country, POOLS.WORLD)
	for i in 20:
		var n: String = pool[rng.randi_range(0, pool.size() - 1)]
		if not taken.has(n):
			return n
	return pool[0] + str(rng.randi_range(2, 99))
