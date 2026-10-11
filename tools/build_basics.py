"""Build Bite/Resources/basics.json from the USDA FoodData Central SR Legacy CSV export.

Usage:
    python tools/build_basics.py <path to FoodData_Central_sr_legacy_food_csv_2018-04> Bite/Resources/basics.json

Download: https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip
USDA FoodData Central data is public domain (CC0).

Nutrients are per 100 g. Drinks are tagged "ml" and use the per 100 g values as per 100 ml,
which is within a few percent for water based drinks.
"""
import csv
import json
import sys

# (name, emoji, fdc_id, unit, French aliases, portions as (label, amount))
BASICS = [
    # Fruit
    ("Apple", "🍎", 171688, "g", ["pomme"], [("1 medium", 182), ("1 small", 149)]),
    ("Banana", "🍌", 173944, "g", ["banane"], [("1 medium", 118), ("1 large", 136)]),
    ("Orange", "🍊", 169097, "g", ["orange"], [("1 orange", 131)]),
    ("Pear", "🍐", 169118, "g", ["poire"], [("1 medium", 178)]),
    ("Strawberries", "🍓", 167762, "g", ["fraises", "fraise"], [("1 bowl", 144)]),
    ("Blueberries", "🫐", 171711, "g", ["myrtilles", "myrtille"], [("1 bowl", 148)]),
    ("Grapes", "🍇", 174683, "g", ["raisin", "raisins"], [("10 grapes", 49), ("1 bowl", 151)]),
    ("Kiwi", "🥝", 168153, "g", ["kiwi"], [("1 kiwi", 69)]),
    ("Mango", "🥭", 169910, "g", ["mangue"], [("1 bowl", 165), ("1 mango", 336)]),
    ("Pineapple", "🍍", 169124, "g", ["ananas"], [("1 slice", 84), ("1 bowl", 165)]),
    ("Watermelon", "🍉", 167765, "g", ["pastèque", "melon d'eau"], [("1 wedge", 286), ("1 bowl", 152)]),
    ("Avocado", "🥑", 171705, "g", ["avocat"], [("½ avocado", 100), ("1 avocado", 201)]),
    ("Peach", "🍑", 169928, "g", ["pêche"], [("1 medium", 150)]),
    ("Cherries", "🍒", 171719, "g", ["cerises", "cerise"], [("10 cherries", 82), ("1 bowl", 154)]),
    # Vegetables
    ("Broccoli", "🥦", 170379, "g", ["brocoli"], [("1 bowl", 91)]),
    ("Carrot", "🥕", 170393, "g", ["carotte", "carottes"], [("1 medium", 61)]),
    ("Tomato", "🍅", 170457, "g", ["tomate", "tomates"], [("1 medium", 123), ("1 cherry tomato", 17)]),
    ("Cucumber", "🥒", 168409, "g", ["concombre"], [("½ cucumber", 150)]),
    ("Lettuce", "🥬", 169247, "g", ["salade", "laitue", "romaine"], [("1 bowl", 47)]),
    ("Spinach", "🥬", 168462, "g", ["épinards", "epinard"], [("1 bowl", 30)]),
    ("Bell pepper", "🫑", 170108, "g", ["poivron"], [("1 medium", 119)]),
    ("Zucchini", "🥒", 169291, "g", ["courgette", "courgettes"], [("1 medium", 196)]),
    ("Onion", "🧅", 170000, "g", ["oignon", "oignons"], [("1 medium", 110)]),
    ("Mushrooms", "🍄", 169251, "g", ["champignons", "champignon"], [("1 bowl", 70)]),
    ("Green beans", "🫛", 169961, "g", ["haricots verts"], [("1 bowl", 100)]),
    ("Sweet potato", "🍠", 168483, "g", ["patate douce"], [("1 medium", 114)]),
    ("Potato, boiled", "🥔", 170438, "g", ["pomme de terre", "pommes de terre", "patate"], [("1 potato", 136)]),
    ("Potato, baked", "🥔", 170093, "g", ["pomme de terre au four"], [("1 medium", 173)]),
    ("Sweet corn", "🌽", 169214, "g", ["maïs"], [("1 bowl", 164)]),
    ("Peas", "🫛", 170419, "g", ["petits pois"], [("1 bowl", 145)]),
    # Eggs, meat, fish
    ("Egg", "🥚", 171287, "g", ["oeuf", "œuf", "oeufs", "œufs"], [("1 large", 50), ("1 medium", 44)]),
    ("Egg white", "🥚", 172183, "g", ["blanc d'oeuf", "blanc d'œuf"], [("1 large", 33)]),
    ("Chicken breast, cooked", "🍗", 171477, "g", ["poulet", "blanc de poulet"], [("½ breast", 86), ("1 breast", 172)]),
    ("Chicken thigh, cooked", "🍗", 172388, "g", ["cuisse de poulet"], [("1 thigh", 116)]),
    ("Ground beef 85%, cooked", "🥩", 174034, "g", ["boeuf haché", "bœuf haché", "steak haché"], [("1 serving", 85)]),
    ("Steak, cooked", "🥩", 173118, "g", ["steak", "boeuf", "bœuf", "entrecôte"], [("1 serving", 85), ("1 steak", 200)]),
    ("Salmon, cooked", "🐟", 175168, "g", ["saumon"], [("1 fillet", 178)]),
    ("Tuna, canned in water", "🐟", 173709, "g", ["thon"], [("1 can", 165)]),
    ("Cod, cooked", "🐟", 171956, "g", ["cabillaud", "morue"], [("1 fillet", 180)]),
    ("Shrimp, cooked", "🦐", 175180, "g", ["crevettes", "crevette"], [("1 serving", 85)]),
    ("Pork tenderloin, cooked", "🥩", 168250, "g", ["filet de porc", "porc"], [("1 serving", 85)]),
    ("Turkey breast, cooked", "🦃", 171496, "g", ["dinde", "blanc de dinde"], [("1 serving", 85)]),
    ("Ham", "🍖", 173864, "g", ["jambon"], [("1 slice", 28)]),
    ("Bacon, cooked", "🥓", 167914, "g", ["lard", "lardons", "bacon"], [("1 slice", 8.1)]),
    ("Tofu, firm", "🫘", 172475, "g", ["tofu"], [("¼ block", 81)]),
    # Dairy
    ("Milk, whole", "🥛", 171265, "ml", ["lait entier", "lait"], [("1 glass", 250), ("1 splash", 15)]),
    ("Milk, semi-skimmed", "🥛", 171267, "ml", ["lait demi-écrémé", "lait"], [("1 glass", 250), ("1 splash", 15)]),
    ("Milk, skim", "🥛", 171269, "ml", ["lait écrémé"], [("1 glass", 250)]),
    ("Greek yogurt, 0%", "🥣", 170894, "g", ["yaourt grec 0%", "yogourt grec"], [("1 pot", 170)]),
    ("Greek yogurt", "🥣", 171304, "g", ["yaourt grec", "yogourt grec"], [("1 pot", 170)]),
    ("Plain yogurt", "🥣", 171284, "g", ["yaourt nature", "yogourt nature", "yaourt"], [("1 pot", 125)]),
    ("Cottage cheese", "🥣", 172182, "g", ["cottage"], [("1 serving", 113)]),
    ("Cheddar", "🧀", 173414, "g", ["cheddar", "fromage"], [("1 slice", 28)]),
    ("Mozzarella", "🧀", 170845, "g", ["mozzarella"], [("1 ball", 125), ("1 serving", 28)]),
    ("Parmesan", "🧀", 171247, "g", ["parmesan"], [("1 tbsp grated", 5)]),
    ("Feta", "🧀", 173420, "g", ["feta"], [("1 serving", 38)]),
    ("Gruyère", "🧀", 171242, "g", ["gruyère", "gruyere", "fromage"], [("1 slice", 28)]),
    ("Emmental", "🧀", 171251, "g", ["emmental", "emmentaler", "fromage suisse"], [("1 slice", 28)]),
    ("Brie", "🧀", 172177, "g", ["brie"], [("1 serving", 28)]),
    ("Cream cheese", "🧀", 173418, "g", ["fromage frais", "philadelphia"], [("1 tbsp", 14.5)]),
    ("Butter", "🧈", 173410, "g", ["beurre"], [("1 tsp", 5), ("1 tbsp", 14.2)]),
    ("Cream", "🥛", 170859, "ml", ["crème", "creme"], [("1 tbsp", 15)]),
    ("Almond milk", "🥛", 174832, "ml", ["lait d'amande"], [("1 glass", 250)]),
    ("Soy milk", "🥛", 172446, "ml", ["lait de soja"], [("1 glass", 250)]),
    # Grains and starches
    ("Rice, cooked", "🍚", 168878, "g", ["riz"], [("1 bowl", 158)]),
    ("Brown rice, cooked", "🍚", 169704, "g", ["riz complet"], [("1 bowl", 202)]),
    ("Rice, dry", "🍚", 168877, "g", ["riz cru"], [("1 portion", 75)]),
    ("Pasta, cooked", "🍝", 169737, "g", ["pâtes", "pates", "spaghetti"], [("1 plate", 220), ("1 bowl", 124)]),
    ("Pasta, dry", "🍝", 169736, "g", ["pâtes crues", "pates crues"], [("1 portion", 100)]),
    ("Oats", "🥣", 173904, "g", ["flocons d'avoine", "avoine", "porridge"], [("1 serving", 40)]),
    ("Granola", "🥣", 171646, "g", ["granola", "muesli"], [("1 serving", 45)]),
    ("White bread", "🍞", 174924, "g", ["pain blanc", "pain de mie", "pain"], [("1 slice", 29)]),
    ("Whole wheat bread", "🍞", 172688, "g", ["pain complet"], [("1 slice", 32)]),
    ("Baguette", "🥖", 172675, "g", ["baguette", "pain"], [("1 slice", 30), ("¼ baguette", 62)]),
    ("Croissant", "🥐", 174987, "g", ["croissant"], [("1 croissant", 57)]),
    ("Bagel", "🥯", 174899, "g", ["bagel"], [("1 bagel", 99)]),
    ("Tortilla wrap", "🫓", 175037, "g", ["wrap", "tortilla"], [("1 wrap", 49)]),
    ("Quinoa, cooked", "🥣", 168917, "g", ["quinoa"], [("1 bowl", 185)]),
    ("Couscous, cooked", "🥣", 169700, "g", ["couscous", "semoule"], [("1 bowl", 157)]),
    ("Cheese pizza", "🍕", 170317, "g", ["pizza"], [("1 slice", 81), ("1 pizza", 452)]),
    # Legumes, nuts, seeds
    ("Lentils, cooked", "🫘", 172421, "g", ["lentilles"], [("1 bowl", 198)]),
    ("Chickpeas, cooked", "🫘", 173757, "g", ["pois chiches"], [("1 bowl", 164)]),
    ("Black beans, cooked", "🫘", 173735, "g", ["haricots noirs"], [("1 bowl", 172)]),
    ("Hummus", "🫘", 174289, "g", ["houmous", "hummus"], [("2 tbsp", 30)]),
    ("Almonds", "🌰", 170567, "g", ["amandes", "amande"], [("1 handful", 28)]),
    ("Walnuts", "🌰", 170187, "g", ["noix"], [("1 handful", 28)]),
    ("Cashews", "🌰", 170162, "g", ["noix de cajou", "cajou"], [("1 handful", 28)]),
    ("Peanuts", "🥜", 173806, "g", ["cacahuètes", "cacahuetes", "arachides"], [("1 handful", 28)]),
    ("Peanut butter", "🥜", 172470, "g", ["beurre de cacahuète", "beurre de cacahuete"], [("1 tbsp", 16)]),
    ("Chia seeds", "🌱", 170554, "g", ["graines de chia", "chia"], [("1 tbsp", 12)]),
    # Fats, sweets, sauces
    ("Olive oil", "🫒", 171413, "g", ["huile d'olive", "huile"], [("1 tbsp", 13.5), ("1 tsp", 4.5)]),
    ("Honey", "🍯", 169640, "g", ["miel"], [("1 tsp", 7), ("1 tbsp", 21)]),
    ("Sugar", "🍬", 169655, "g", ["sucre"], [("1 tsp", 4.2), ("1 cube", 2.3)]),
    ("Dark chocolate", "🍫", 170273, "g", ["chocolat noir", "chocolat"], [("1 square", 10), ("1 bar", 100)]),
    ("Jam", "🫙", 169641, "g", ["confiture"], [("1 tbsp", 20)]),
    ("Mayonnaise", "🫙", 171009, "g", ["mayo", "mayonnaise"], [("1 tbsp", 13.8)]),
    ("Tomato sauce", "🍅", 171192, "g", ["sauce tomate", "sauce pâtes"], [("1 serving", 132)]),
    ("Chocolate chip cookie", "🍪", 172716, "g", ["cookie", "biscuit"], [("1 cookie", 13)]),
    ("Vanilla ice cream", "🍦", 167575, "g", ["glace vanille", "glace"], [("1 scoop", 66)]),
    # Drinks
    ("Coffee, black", "☕", 171890, "ml", ["café", "cafe", "espresso"], [("1 cup", 240)]),
    ("Orange juice", "🧃", 169098, "ml", ["jus d'orange"], [("1 glass", 250)]),
    ("Beer", "🍺", 168746, "ml", ["bière", "biere"], [("1 bottle", 330), ("1 pint", 500)]),
    ("Red wine", "🍷", 173190, "ml", ["vin rouge", "vin"], [("1 glass", 150)]),
    ("White wine", "🥂", 174837, "ml", ["vin blanc", "vin"], [("1 glass", 150)]),
    ("Cola", "🥤", 174852, "ml", ["coca", "soda"], [("1 can", 330)]),
]

# Each basic's name in French and Spanish (Spain), as it reads on a menu or a pack there.
NAMES = {
    "Apple": ("Pomme", "Manzana"),
    "Banana": ("Banane", "Plátano"),
    "Orange": ("Orange", "Naranja"),
    "Pear": ("Poire", "Pera"),
    "Strawberries": ("Fraises", "Fresas"),
    "Blueberries": ("Myrtilles", "Arándanos"),
    "Grapes": ("Raisin", "Uvas"),
    "Kiwi": ("Kiwi", "Kiwi"),
    "Mango": ("Mangue", "Mango"),
    "Pineapple": ("Ananas", "Piña"),
    "Watermelon": ("Pastèque", "Sandía"),
    "Avocado": ("Avocat", "Aguacate"),
    "Peach": ("Pêche", "Melocotón"),
    "Cherries": ("Cerises", "Cerezas"),
    "Broccoli": ("Brocoli", "Brócoli"),
    "Carrot": ("Carotte", "Zanahoria"),
    "Tomato": ("Tomate", "Tomate"),
    "Cucumber": ("Concombre", "Pepino"),
    "Lettuce": ("Salade verte", "Lechuga"),
    "Spinach": ("Épinards", "Espinacas"),
    "Bell pepper": ("Poivron", "Pimiento"),
    "Zucchini": ("Courgette", "Calabacín"),
    "Onion": ("Oignon", "Cebolla"),
    "Mushrooms": ("Champignons", "Champiñones"),
    "Green beans": ("Haricots verts", "Judías verdes"),
    "Sweet potato": ("Patate douce", "Boniato"),
    "Potato, boiled": ("Pomme de terre à l'eau", "Patata cocida"),
    "Potato, baked": ("Pomme de terre au four", "Patata asada"),
    "Sweet corn": ("Maïs doux", "Maíz dulce"),
    "Peas": ("Petits pois", "Guisantes"),
    "Egg": ("Œuf", "Huevo"),
    "Egg white": ("Blanc d'œuf", "Clara de huevo"),
    "Chicken breast, cooked": ("Blanc de poulet, cuit", "Pechuga de pollo cocinada"),
    "Chicken thigh, cooked": ("Cuisse de poulet, cuite", "Muslo de pollo cocinado"),
    "Ground beef 85%, cooked": ("Steak haché 15 % MG, cuit", "Carne picada 15 % grasa, cocinada"),
    "Steak, cooked": ("Steak, cuit", "Filete de ternera a la plancha"),
    "Salmon, cooked": ("Saumon, cuit", "Salmón cocinado"),
    "Tuna, canned in water": ("Thon au naturel", "Atún al natural"),
    "Cod, cooked": ("Cabillaud, cuit", "Bacalao cocinado"),
    "Shrimp, cooked": ("Crevettes, cuites", "Gambas cocidas"),
    "Pork tenderloin, cooked": ("Filet mignon de porc, cuit", "Solomillo de cerdo cocinado"),
    "Turkey breast, cooked": ("Blanc de dinde, cuit", "Pechuga de pavo cocinada"),
    "Ham": ("Jambon blanc", "Jamón cocido"),
    "Bacon, cooked": ("Bacon grillé", "Beicon a la plancha"),
    "Tofu, firm": ("Tofu ferme", "Tofu firme"),
    "Milk, whole": ("Lait entier", "Leche entera"),
    "Milk, semi-skimmed": ("Lait demi-écrémé", "Leche semidesnatada"),
    "Milk, skim": ("Lait écrémé", "Leche desnatada"),
    "Greek yogurt, 0%": ("Yaourt grec 0 %", "Yogur griego 0 %"),
    "Greek yogurt": ("Yaourt grec", "Yogur griego"),
    "Plain yogurt": ("Yaourt nature", "Yogur natural"),
    "Cottage cheese": ("Cottage cheese", "Queso cottage"),
    "Cheddar": ("Cheddar", "Queso cheddar"),
    "Mozzarella": ("Mozzarella", "Mozzarella"),
    "Parmesan": ("Parmesan", "Parmesano"),
    "Feta": ("Feta", "Queso feta"),
    "Gruyère": ("Gruyère", "Queso gruyère"),
    "Emmental": ("Emmental", "Queso emmental"),
    "Brie": ("Brie", "Queso brie"),
    "Cream cheese": ("Fromage frais à tartiner", "Queso crema"),
    "Butter": ("Beurre", "Mantequilla"),
    "Cream": ("Crème liquide", "Nata líquida"),
    "Almond milk": ("Lait d'amande", "Bebida de almendra"),
    "Soy milk": ("Lait de soja", "Bebida de soja"),
    "Rice, cooked": ("Riz, cuit", "Arroz cocido"),
    "Brown rice, cooked": ("Riz complet, cuit", "Arroz integral cocido"),
    "Rice, dry": ("Riz, cru", "Arroz crudo"),
    "Pasta, cooked": ("Pâtes, cuites", "Pasta cocida"),
    "Pasta, dry": ("Pâtes, crues", "Pasta cruda"),
    "Oats": ("Flocons d'avoine", "Copos de avena"),
    "Granola": ("Granola", "Granola"),
    "White bread": ("Pain de mie", "Pan de molde"),
    "Whole wheat bread": ("Pain complet", "Pan integral"),
    "Baguette": ("Baguette", "Barra de pan"),
    "Croissant": ("Croissant", "Cruasán"),
    "Bagel": ("Bagel", "Bagel"),
    "Tortilla wrap": ("Wrap", "Tortilla de trigo"),
    "Quinoa, cooked": ("Quinoa, cuit", "Quinoa cocida"),
    "Couscous, cooked": ("Couscous, cuit", "Cuscús cocido"),
    "Cheese pizza": ("Pizza margherita", "Pizza margarita"),
    "Lentils, cooked": ("Lentilles, cuites", "Lentejas cocidas"),
    "Chickpeas, cooked": ("Pois chiches, cuits", "Garbanzos cocidos"),
    "Black beans, cooked": ("Haricots noirs, cuits", "Alubias negras cocidas"),
    "Hummus": ("Houmous", "Hummus"),
    "Almonds": ("Amandes", "Almendras"),
    "Walnuts": ("Noix", "Nueces"),
    "Cashews": ("Noix de cajou", "Anacardos"),
    "Peanuts": ("Cacahuètes", "Cacahuetes"),
    "Peanut butter": ("Beurre de cacahuète", "Crema de cacahuete"),
    "Chia seeds": ("Graines de chia", "Semillas de chía"),
    "Olive oil": ("Huile d'olive", "Aceite de oliva"),
    "Honey": ("Miel", "Miel"),
    "Sugar": ("Sucre", "Azúcar"),
    "Dark chocolate": ("Chocolat noir", "Chocolate negro"),
    "Jam": ("Confiture", "Mermelada"),
    "Mayonnaise": ("Mayonnaise", "Mayonesa"),
    "Tomato sauce": ("Sauce tomate", "Salsa de tomate"),
    "Chocolate chip cookie": ("Cookie aux pépites de chocolat", "Galleta con pepitas de chocolate"),
    "Vanilla ice cream": ("Glace à la vanille", "Helado de vainilla"),
    "Coffee, black": ("Café noir", "Café solo"),
    "Orange juice": ("Jus d'orange", "Zumo de naranja"),
    "Beer": ("Bière", "Cerveza"),
    "Red wine": ("Vin rouge", "Vino tinto"),
    "White wine": ("Vin blanc", "Vino blanco"),
    "Cola": ("Cola", "Refresco de cola"),
}

# The usual French and Spanish words for each portion.
PORTIONS = {
    "1 avocado": ("1 avocat", "1 aguacate"),
    "1 bagel": ("1 bagel", "1 bagel"),
    "1 ball": ("1 boule", "1 bola"),
    "1 bar": ("1 tablette", "1 tableta"),
    "1 bottle": ("1 bouteille", "1 botellín"),
    "1 bowl": ("1 bol", "1 bol"),
    "1 breast": ("1 blanc", "1 pechuga"),
    "1 can": ("1 boîte", "1 lata"),
    "1 cherry tomato": ("1 tomate cerise", "1 tomate cherry"),
    "1 cookie": ("1 cookie", "1 galleta"),
    "1 croissant": ("1 croissant", "1 cruasán"),
    "1 cube": ("1 morceau", "1 terrón"),
    "1 cup": ("1 tasse", "1 taza"),
    "1 fillet": ("1 filet", "1 filete"),
    "1 glass": ("1 verre", "1 vaso"),
    "1 handful": ("1 poignée", "1 puñado"),
    "1 kiwi": ("1 kiwi", "1 kiwi"),
    "1 large": ("1 gros", "1 grande"),
    "1 mango": ("1 mangue", "1 mango"),
    "1 medium": ("1 moyen", "1 mediano"),
    "1 orange": ("1 orange", "1 naranja"),
    "1 pint": ("1 pinte", "1 pinta"),
    "1 pizza": ("1 pizza", "1 pizza"),
    "1 plate": ("1 assiette", "1 plato"),
    "1 portion": ("1 portion", "1 ración"),
    "1 pot": ("1 pot", "1 envase"),
    "1 potato": ("1 pomme de terre", "1 patata"),
    "1 scoop": ("1 boule", "1 bola"),
    "1 serving": ("1 portion", "1 ración"),
    "1 slice": ("1 tranche", "1 rebanada"),
    "1 small": ("1 petit", "1 pequeño"),
    "1 splash": ("1 nuage", "1 chorrito"),
    "1 square": ("1 carré", "1 onza"),
    "1 steak": ("1 steak", "1 filete"),
    "1 tbsp": ("1 c. à soupe", "1 cucharada"),
    "1 tbsp grated": ("1 c. à soupe, râpé", "1 cucharada, rallado"),
    "1 thigh": ("1 cuisse", "1 muslo"),
    "1 tsp": ("1 c. à café", "1 cucharadita"),
    "1 wedge": ("1 tranche", "1 tajada"),
    "1 wrap": ("1 wrap", "1 tortilla"),
    "10 cherries": ("10 cerises", "10 cerezas"),
    "10 grapes": ("10 grains", "10 uvas"),
    "2 tbsp": ("2 c. à soupe", "2 cucharadas"),
    "¼ baguette": ("¼ de baguette", "¼ de barra"),
    "¼ block": ("¼ de bloc", "¼ de bloque"),
    "½ avocado": ("½ avocat", "½ aguacate"),
    "½ breast": ("½ blanc", "½ pechuga"),
    "½ cucumber": ("½ concombre", "½ pepino"),
}

# Where a food needs its own word, or the adjective agrees with a feminine noun.
PORTION_OVERRIDES = {
    ("Apple", "1 medium"): ("1 moyenne", "1 mediana"),
    ("Apple", "1 small"): ("1 petite", "1 pequeña"),
    ("Banana", "1 medium"): ("1 moyenne", "1 mediano"),
    ("Banana", "1 large"): ("1 grosse", "1 grande"),
    ("Pear", "1 medium"): ("1 moyenne", "1 mediana"),
    ("Carrot", "1 medium"): ("1 moyenne", "1 mediana"),
    ("Tomato", "1 medium"): ("1 moyenne", "1 mediano"),
    ("Zucchini", "1 medium"): ("1 moyenne", "1 mediano"),
    ("Onion", "1 medium"): ("1 moyen", "1 mediana"),
    ("Sweet potato", "1 medium"): ("1 moyenne", "1 mediano"),
    ("Potato, baked", "1 medium"): ("1 moyenne", "1 mediana"),
    ("Peach", "1 medium"): ("1 moyenne", "1 mediano"),
    ("Pineapple", "1 slice"): ("1 tranche", "1 rodaja"),
    ("Ham", "1 slice"): ("1 tranche", "1 loncha"),
    ("Bacon, cooked", "1 slice"): ("1 tranche", "1 loncha"),
    ("Cheddar", "1 slice"): ("1 tranche", "1 loncha"),
    ("Gruyère", "1 slice"): ("1 tranche", "1 loncha"),
    ("Emmental", "1 slice"): ("1 tranche", "1 loncha"),
    ("Cheese pizza", "1 slice"): ("1 part", "1 porción"),
    ("Cola", "1 can"): ("1 canette", "1 lata"),
}


def translations(name: str, portions: list) -> tuple[dict, list]:
    """The French and Spanish name, and each portion with its French and Spanish label."""
    fr, es = NAMES[name]
    labelled = []
    for label, amount in portions:
        pfr, pes = PORTION_OVERRIDES.get((name, label), PORTIONS[label])
        labelled.append({"label": label, "amount": amount, "labels": {"fr": pfr, "es": pes}})
    return {"fr": fr, "es": es}, labelled


NUTRIENTS = {
    "1008": "kcal",
    "1003": "protein",
    "1005": "carbs",
    "1004": "fat",
    "2000": "sugar",
    "1079": "fiber",
    "1258": "saturatedFat",
    "1093": "sodium_mg",
}


def main(src: str, out: str) -> None:
    wanted = {str(b[2]) for b in BASICS}
    values: dict[str, dict[str, float]] = {i: {} for i in wanted}
    with open(f"{src}/food_nutrient.csv", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["fdc_id"] in wanted and row["nutrient_id"] in NUTRIENTS:
                values[row["fdc_id"]][NUTRIENTS[row["nutrient_id"]]] = float(row["amount"])

    items = []
    for name, emoji, fdc, unit, aliases, portions in BASICS:
        v = values[str(fdc)]
        missing = [k for k in ("kcal", "protein", "carbs", "fat") if k not in v]
        if missing:
            raise SystemExit(f"{name} ({fdc}) is missing {missing}")
        sodium = v.get("sodium_mg")
        names, labelled = translations(name, portions)
        items.append({
            "id": fdc,
            "name": name,
            "names": names,
            "emoji": emoji,
            "unit": unit,
            "aliases": aliases,
            "kcal": round(v["kcal"], 1),
            "protein": round(v["protein"], 2),
            "carbs": round(v["carbs"], 2),
            "fat": round(v["fat"], 2),
            "sugar": round(v["sugar"], 2) if "sugar" in v else None,
            "fiber": round(v["fiber"], 2) if "fiber" in v else None,
            "saturatedFat": round(v["saturatedFat"], 2) if "saturatedFat" in v else None,
            # Salt is sodium x 2.5, the EU labelling convention.
            "salt": round(sodium * 2.5 / 1000, 3) if sodium is not None else None,
            "portions": labelled,
        })

    with open(out, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=1)
    print(f"wrote {len(items)} basics to {out}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
