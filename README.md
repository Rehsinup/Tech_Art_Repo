## 1. Construire un matériau éclairé en HLSL

Avec ces shaders, ma démarche est de décomposer le rendu d’un matériau pour comprendre le rôle de chaque calcul : comment une texture est appliquée, comment la lumière réagit à la surface et comment ajouter des reflets ou de l’émission. Le HLSL me permet de travailler directement sur ces différentes étapes.

### Une base texturée

Dans `BaseShader.shader`, je transforme les positions des sommets avec `TransformObjectToHClip`, puis je transmets les UV au fragment shader. J’applique le tiling et l’offset du matériau pour pouvoir ajuster la répétition et le placement de la texture.

La couleur de départ est simplement la texture multipliée par une teinte :

```hlsl
float4 textureSample = tex2D(_BaseTex, i.uv);
return textureSample * _BaseColor;
```

Cette base me donne un point de départ simple pour isoler les contributions que j’utilise dans `TextureShader.shader`.

### Éclairage diffus et ambiant

Pour le diffus, j’utilise le produit scalaire entre la normale de la surface et la direction de la lumière principale. Plus la surface fait face à la lumière, plus sa contribution est forte. Je limite le résultat à zéro pour éviter une contribution négative sur les faces opposées.

```hlsl
float3 diffuse = mainLight.color * max(0, dot(i.normalWS, mainLight.direction));
float3 ambient = SampleSH(i.normalWS);
```

J’ajoute une contribution ambiante avec `SampleSH`, puis je multiplie la couleur texturée par la somme du diffus et de l’ambiant. Cette séparation me permet de comprendre ce qui vient de la lumière directe et ce qui vient de l’environnement lumineux.

### Reflet spéculaire et Fresnel

Pour le reflet spéculaire, je calcule un demi-vecteur entre la direction de la lumière et celle de la caméra :

```hlsl
float3 halfVector = normalize(mainLight.direction + i.viewWS);
float specular = pow(max(0, dot(i.normalWS, halfVector)), _GlossPower);
```

J’expose `_GlossPower` pour contrôler la concentration du reflet. Une valeur élevée donne un reflet plus resserré.

J’utilise également un terme Fresnel pour accentuer les surfaces vues sous un angle rasant :

```hlsl
float fresnel = pow(1.0f - max(0, dot(i.normalWS, i.viewWS)), _FresnelPower);
```

Dans mon implémentation, ce terme est multiplié par le diffus. L’accentuation des bords reste donc liée à l’éclairage direct. `_FresnelPower` me permet de régler la répartition de cet effet.

### Émission

J’ai prévu une variante activable avec `ENABLE_EMSSIVE`, qui ajoute `_EmissiveColor` au résultat. Cela me permet de contrôler une contribution colorée indépendante du calcul diffus.

Cette addition agit sur la couleur du matériau. Pour obtenir un halo autour des zones lumineuses, il faut aussi un post-traitement adapté, comme le bloom.

### Alpha clipping et dithering

J’explore deux façons de découper le matériau. La première supprime les fragments dont l’alpha est inférieur à `_ClipThreshold`. La seconde utilise une matrice de 16 seuils répétée en motif 4 × 4 : chaque fragment est conservé ou supprimé selon son alpha et sa position dans le motif.

L’intérêt du dithering est de répartir les fragments visibles pour produire une impression de transparence par découpage. Les deux tests sont présents dans le shader actuel.

Cette partie reste à ajuster : mon appel à `ComputeScreenPos` utilise actuellement la position objet, alors que les coordonnées nécessaires au motif écran doivent être calculées à partir de la position projetée.

### Tester les modes de transparence

Dans `TransparentShader.shader`, j’expose les facteurs de mélange source et destination :

```hlsl
Blend [_SrcBlend] [_DstBlend]
```

Cela me permet de modifier la manière dont la couleur du matériau se combine avec ce qui est déjà affiché. Le réglage par défaut est additif (`One / One`).

L’ensemble reste un terrain d’expérimentation : le calcul diffus de `TextureShader.shader`, par exemple, n’applique pas encore explicitement l’atténuation des ombres de la lumière principale.

## 2. Utiliser la profondeur et le stencil

Avec ces effets, je travaille sur la visibilité des surfaces : faire ressortir une intersection, afficher une partie masquée ou limiter un matériau à une zone précise. La profondeur et le stencil permettent de piloter ces comportements directement pendant le rendu.

### Faire ressortir les intersections

Dans `Intersection.shader`, je lis la profondeur de la scène avec `SampleSceneDepth`, puis je la convertis avec `LinearEyeDepth`. Je compare cette profondeur à celle du fragment pour construire un masque de proximité.

```hlsl
float intersectAmount = sceneEyeDepth - i.positionSS.w;
intersectAmount = saturate(1.0f - intersectAmount);
intersectAmount = pow(intersectAmount, _IntersectionPower);
return lerp(_BaseColor, _IntersectionColor, intersectAmount);
```

Lorsque les profondeurs sont proches, le shader privilégie `_IntersectionColor`. `_IntersectionPower` règle la transition entre cette couleur et `_BaseColor`.

L’objectif est de faire apparaître visuellement les zones de contact entre surfaces à partir des informations de profondeur. Cette approche dépend de la texture de profondeur fournie par la caméra et le pipeline. Le shader actuel possède des tags de transparence, mais pas de commande `Blend` : la semi-transparence reste donc à configurer si je veux l’utiliser.

### Afficher les parties cachées avec un effet X-ray

Dans `Xray.shader`, j’utilise :

```hlsl
ZTest Greater
ZWrite Off
```

Le test de profondeur conserve les fragments situés derrière une profondeur déjà écrite, puis je leur applique `_BaseColor`. Je désactive l’écriture de profondeur pour que cette passe ne remplace pas les informations déjà présentes.

C’est une base pour révéler la silhouette d’un objet derrière un obstacle. Le fonctionnement dépend aussi de l’ordre de rendu : l’obstacle doit avoir écrit sa profondeur avant le passage de l’effet.

### Masquer une zone avec le stencil

J’ai séparé cette expérimentation en deux shaders : `StencilMask.shader` et `StencilTexture.shader`.

Le premier écrit une référence dans le stencil avec `Comp Always` et `Pass Replace`. Je le place dans la file `Geometry-1` pour qu’il passe avant la géométrie standard.

Le second utilise `Comp Equal` et n’affiche sa texture que là où la référence correspond.

Cette séparation me permet de définir une forme de masque d’un côté et le contenu visible de l’autre. Elle peut servir de base à une fenêtre de visibilité ou à un effet de révélation localisé. Il reste à finaliser le comportement couleur du masque : `ZWrite Off` désactive son écriture de profondeur, mais je n’ai pas encore ajouté `ColorMask 0` pour empêcher explicitement son écriture dans le rendu couleur.

## 3. Texturer avec une projection triplanaire

Avec `Triplanar.shader`, j’explore une manière d’appliquer une texture sans utiliser les UV du modèle. Le principe est de projeter la même texture selon trois axes, puis de mélanger ces projections en fonction de l’orientation de la surface.

### Construire les trois projections

J’utilise la position en espace monde pour obtenir trois jeux de coordonnées :

```hlsl
float2 xAxisUV = i.positionWS.zy * _Tile;
float2 yAxisUV = i.positionWS.xz * _Tile;
float2 zAxisUV = i.positionWS.xy * _Tile;
```

Chaque paire de composantes correspond à une projection. `_Tile` me permet de contrôler la répétition de la texture.

### Mélanger selon les normales

Je calcule les poids à partir des composantes absolues de la normale, puis je les normalise pour que leur somme soit égale à un :

```hlsl
float3 weights = pow(abs(i.normalWS), _BlendPower);
weights *= rcp(weights.x + weights.y + weights.z);
```

Je multiplie ensuite chaque échantillon de texture par son poids avant de les additionner. Une face orientée principalement vers un axe utilise surtout la projection associée. Les zones intermédiaires combinent plusieurs projections.

J’expose `_BlendPower` pour ajuster la transition : une valeur plus élevée renforce la projection dominante et rend le mélange plus net.

Cette approche permet de se passer du dépliage UV pour ce matériau, au prix de trois échantillonnages de texture. Comme les coordonnées sont prises dans le monde, la projection reste ancrée dans cet espace : déplacer le modèle change la portion de texture qu’il traverse.

Le paramètre `_BaseColor` est présent dans le shader, mais je ne l’utilise pas encore dans la couleur finale.

## 4. Construire une traînée animée avec Shader Graph

Dans `Trails.shadergraph`, je combine une texture défilante, un bruit animé et un dégradé de couleur. L’objectif est de contrôler séparément le mouvement du motif, la variation de son opacité et sa couleur le long de la traînée.

Le graphe définit le matériau de l’effet. La forme de la traînée dépend de la géométrie sur laquelle il est appliqué et de ses UV.

### Animer la texture et le bruit séparément

Pour faire défiler la texture principale, je multiplie le temps par `MainTexSpeed`, puis j’envoie le résultat dans l’offset des UV.

J’utilise une deuxième chaîne pour le bruit : le temps est multiplié par `DissolveSpeed`, puis appliqué aux coordonnées d’un `Simple Noise`.

```text
Temps × MainTexSpeed  → déplacement des UV → texture principale
Temps × DissolveSpeed → déplacement des UV → bruit
```

Ces deux vitesses indépendantes me permettent de régler le mouvement de la texture sans imposer le même mouvement au masque. `DissolveScale` contrôle l’échelle du bruit.

### Répartir les couleurs le long de la traînée

Je récupère la composante U des UV pour piloter un `Lerp` entre `Color1` et `Color2`. Le dégradé suit ainsi un axe de la géométrie.

Je multiplie ce dégradé par la texture masquée, puis j’envoie le résultat dans `Base Color`. La chaîne de couleur n’est actuellement pas connectée à l’émission.

### Atténuer une extrémité avec un masque

Pour faire varier le masque le long de la traînée, je combine le bruit avec U. Le graphe utilise `One Minus`, une addition et une soustraction, ce qui correspond à :

```text
masque = bruit + (1 − U) − U
       = bruit + 1 − 2U
```

Le masque favorise une extrémité et atténue progressivement l’autre, tandis que le bruit ajoute des variations animées.

Je multiplie ensuite ce masque par la texture. Le résultat sert à moduler la couleur et passe également par un `Clamp` entre 0 et 1 pour alimenter l’alpha. Le matériau utilise une surface transparente avec l’alpha clipping activé.

La dissolution repose ici sur le défilement du bruit et sur la variation du masque dans les UV. Je n’ai pas encore exposé de paramètre unique permettant de piloter une disparition complète de l’effet de 0 à 1.

### Paramètres du matériau

| Paramètre | Utilisation |
| --- | --- |
| `MainTex` | Choisir le motif principal. |
| `MainTexSpeed` | Régler la direction et la vitesse de la texture. |
| `DissolveSpeed` | Régler la direction et la vitesse du bruit. |
| `DissolveScale` | Modifier l’échelle du bruit. |
| `Color1` et `Color2` | Définir les couleurs du dégradé. |

Ces paramètres regroupent les réglages de l’effet dans le matériau pour pouvoir créer des variations sans modifier les connexions du graphe.

## 7. Autres expérimentations et travail en cours

### Échantillonner une cubemap

Avec `CubemapShader.shader`, j’explore l’utilisation d’une texture cubique. Je transforme la normale en espace monde, puis je m’en sers comme direction pour échantillonner la cubemap.

Cette approche me permet d’associer une couleur à l’orientation de la surface. Le shader ne calcule pas encore un vecteur de réflexion dépendant de la caméra : il s’agit d’une première exploration de l’échantillonnage d’une cubemap.

### Construire un shader PBR

Dans `PBR.shader`, ma démarche est de relier les propriétés du matériau au modèle d’éclairage d’URP. Je prépare une structure `SurfaceData` pour les caractéristiques de la surface et une structure `InputData` pour les informations nécessaires à son éclairage, puis j’appelle `UniversalFragmentPBR`.

Le shader prévoit des entrées pour la couleur de base, le métallique, la douceur de surface, les normales, l’émission et l’occlusion ambiante. Cette organisation permet de séparer les données du matériau des informations liées à sa position, à son orientation et à la vue.

Cette partie est encore en cours. Les calculs du métallique, de la douceur et des normales utilisent actuellement `_BaseTex` au lieu de leurs textures dédiées. La branche de lightmap dynamique contient également `bakedGO` à la place de `bakedGI`. Ces points doivent être corrigés avant de considérer ce shader comme finalisé.

### Préparer un matériau de bouclier

`Shield.shadergraph` est pour le moment une base de matériau Lit. Les blocs de sortie sont présents, mais aucun réseau de nœuds ne construit encore l’effet de bouclier. Je le garde donc comme une expérimentation à développer.
