from flask import Flask, request, jsonify
from flask_cors import CORS
import re, datetime, feedparser, requests, wikipedia
from urllib.parse import quote_plus
from PyDictionary import PyDictionary as diction

app = Flask(__name__)

# ✅ Enable CORS for all routes (you can restrict later if needed)
CORS(app, resources={r"/*": {"origins": "*"}})

# ----------------- Utility helpers -----------------
def fetch_top_news(max_items=5):
    try:
        feed_url = "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en"
        feed = feedparser.parse(feed_url)
        headlines = [entry.title for entry in feed.entries[:max_items]]
        return headlines
    except Exception as e:
        print("News error:", e)
        return []

def ip_loc():
    try:
        r = requests.get("https://ipinfo.io/json", timeout=4).json()
        loc = r.get("loc")
        city = r.get("city")
        if loc:
            lat, lon = map(float, loc.split(","))
            return lat, lon, city
    except:
        pass
    return 12.9165, 79.1325, "Vellore"

def geocode(city_name):
    try:
        url = "https://nominatim.openstreetmap.org/search"
        params = {"q": city_name, "format": "json", "limit": 1}
        r = requests.get(url, params=params, timeout=5, headers={"User-Agent":"Jarvis/1.0"})
        arr = r.json()
        if arr:
            return float(arr[0]["lat"]), float(arr[0]["lon"])
    except:
        pass
    return None, None

def fetch_weather_for(lat, lon):
    try:
        url = "https://api.open-meteo.com/v1/forecast"
        params = {"latitude": lat, "longitude": lon, "current_weather": True}
        r = requests.get(url, params=params, timeout=6).json()
        cw = r.get('current_weather')
        if cw:
            return {
                "temperature": cw.get("temperature"),
                "windspeed": cw.get("windspeed"),
                "desc": f"{cw.get('temperature')}°C, wind {cw.get('windspeed')} km/h"
            }
    except:
        pass
    return None

def calculate_expression(expr):
    try:
        expr = expr.replace("x", "*").replace("times", "*").replace("plus", "+").replace("minus", "-")
        expr = expr.replace("divided by", "/").replace("over", "/")
        expr = re.sub(r'[^0-9\+\-\*\/\.\(\) ]', '', expr)
        result = eval(expr)
        return result
    except:
        return None

def get_recipe(dish):
    try:
        url = f"https://www.themealdb.com/api/json/v1/1/search.php?s={quote_plus(dish)}"
        resp = requests.get(url, timeout=6).json()
        meals = resp.get("meals")
        if meals:
            meal = meals[0]
            ingredients = []
            for i in range(1, 21):
                ing = meal.get(f"strIngredient{i}")
                meas = meal.get(f"strMeasure{i}")
                if ing and ing.strip():
                    ingredients.append(f"{meas.strip()} {ing.strip()}" if meas else ing.strip())
            return {
                "name": meal.get("strMeal"),
                "area": meal.get("strArea"),
                "category": meal.get("strCategory"),
                "ingredients": ingredients,
                "instructions": meal.get("strInstructions")
            }
    except Exception as e:
        print("MealDB error:", e)
    return None

def answer_fact_query(text):
    try:
        res = wikipedia.search(text, results=1)
        if res:
            return wikipedia.summary(res[0], sentences=2)
    except:
        return "No information found."
    return "No results found."

# ----------------- API Routes -----------------
@app.route('/')
def home():
    return jsonify({"status": "Jarvis API running", "time": datetime.datetime.now().isoformat()})

@app.route('/ask', methods=['POST'])
def ask():
    data = request.json
    query = data.get('query', '').lower().strip()
    response = "Sorry, I didn't understand that."

    if not query:
        return jsonify({"reply": "Please provide a query."})

    # Match by keywords
    if "weather" in query:
        city_match = re.search(r'in\s+([a-zA-Z\s]+)', query)
        city = city_match.group(1).strip() if city_match else None
        if city:
            lat, lon = geocode(city)
        else:
            lat, lon, city = ip_loc()
        w = fetch_weather_for(lat, lon)
        if w:
            response = f"Weather in {city}: {w['desc']}"
        else:
            response = "Unable to fetch weather."

    elif "news" in query or "headlines" in query:
        news = fetch_top_news(5)
        response = "Top headlines: " + " | ".join(news)

    elif any(k in query for k in ["calculate", "plus", "minus", "times", "divided", "x", "over"]):
        expr = re.sub(r'(calculate|what is|equals)', '', query)
        result = calculate_expression(expr)
        response = f"The answer is {result}" if result is not None else "Could not calculate that."

    elif any(k in query for k in ["recipe", "how to make", "cook", "make"]):
        m = re.search(r'(?:recipe for|make|cook)\s+(.+)', query)
        dish = m.group(1) if m else query.replace("recipe", "").strip()
        recipe = get_recipe(dish)
        if recipe:
            response = f"Recipe for {recipe['name']}: {recipe['area']} cuisine. Ingredients: {', '.join(recipe['ingredients'][:5])}..."
        else:
            response = "Sorry, no recipe found."

    elif any(k in query for k in ["who is", "what is", "tell me about", "define"]):
        response = answer_fact_query(query)

    elif "joke" in query:
        import pyjokes
        response = pyjokes.get_joke()

    elif "meaning" in query:
        word = re.sub(r'.*meaning of\s*', '', query)
        res = diction.meaning(word)
        response = f"Meaning of {word}: {res}"

    elif "synonym" in query:
        word = re.sub(r'.*synonym of\s*', '', query)
        res = diction.synonym(word)
        response = f"Synonym of {word}: {res}"

    elif "antonym" in query:
        word = re.sub(r'.*antonym of\s*', '', query)
        res = diction.antonym(word)
        response = f"Antonym of {word}: {res}"

    return jsonify({"query": query, "reply": response})

@app.route('/weather')
def weather_endpoint():
    city = request.args.get("city", "Vellore")
    lat, lon = geocode(city)
    if not lat:
        lat, lon, city = ip_loc()
    w = fetch_weather_for(lat, lon)
    if not w:
        return jsonify({"error": "Weather unavailable"}), 404
    return jsonify({"city": city, "temperature": w['temperature'], "windspeed": w['windspeed']})

@app.route('/recipe')
def recipe_endpoint():
    dish = request.args.get("dish")
    if not dish:
        return jsonify({"error": "Missing dish"}), 400
    r = get_recipe(dish)
    if not r:
        return jsonify({"error": "Recipe not found"}), 404
    return jsonify(r)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
