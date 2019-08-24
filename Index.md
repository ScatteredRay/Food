---
Title: Recipes
---

Food and recipes!

Recipes:

{% for recipe in site.recipes %}
   [{{ recipe.Title }}]({{ recipe.url }})
{% endfor %}

