---
Title: Indy's Recipes and related food stuff.
display_section: recipes
---

Food and recipes!

Recipes:

{% for recipe in site.recipes %}
   [{{ recipe.Title }}]({{ recipe.url }})
{% endfor %}

