Food and recipes

{% for recipe in site.recipes %}
   <a href="{{ recipe.url | prepend: site.baseurl }}">
       <h2>{{ recipe.title }}</h2>
   </a>
{% endfor %}
