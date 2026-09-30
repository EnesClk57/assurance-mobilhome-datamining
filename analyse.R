# =============================================================================
# Projet Data Mining - Partie 2 : Segmentation et Scoring
# Cas : Assurance Mobil-Home
# Auteurs : ESER Enes, MARFOUK Omar (BUT Science des Données - VCOD)
#
# Les lignes marquées [AJOUT] ne figuraient pas dans le rapport : elles relient
# les blocs de code entre eux (chargement des données, graine aléatoire...).
# =============================================================================

# ---- 0. PACKAGES ET DONNÉES -------------------------------------------------
# [AJOUT] install.packages(c("readxl", "FactoMineR", "factoextra", "cluster",
#                            "dplyr", "caret"))
library(readxl)      # [AJOUT] lecture du fichier Excel
library(FactoMineR)  # AFCM
library(factoextra)  # graphiques de l'AFCM
library(cluster)     # CAH (agnes)
library(dplyr)       # équilibrage des données
library(caret)       # découpage train/test, matrice de confusion

set.seed(123)  # [AJOUT] résultats reproductibles (K-means, échantillonnage)

# [AJOUT] Le tableau recodé (5 822 lignes, 10 colonnes) est dans l'onglet
# "tableau recode" du fichier Assurance.xlsx (nettoyage et recodage faits sous Excel)
donnees <- read_excel("Assurance.xlsx", sheet = "tableau recode")
donnees <- as.data.frame(lapply(donnees, as.factor))  # [AJOUT] variables qualitatives

str(donnees)
table(donnees$Mobilhome)  # 348 clients assurés vs 5 474 non assurés


# ---- 1. AFCM (Analyse Factorielle des Correspondances Multiples) ------------
# On affiche les noms pour trouver où est "cust"
names(donnees)

# quali.sup = 3 : la 3ème colonne ("cust") ne participe pas à la construction des axes
# graph = TRUE  : affiche le nuage de points
res.mca <- MCA(donnees, quali.sup = 3, graph = TRUE)

# Affiche les variables les plus liées à l'Axe 1 et à l'Axe 2
dimdesc(res.mca, axes = 1:2)


# ---- 2. K-MEANS ET MÉTHODE DU COUDE -----------------------------------------
# 1. On récupère les coordonnées des clients calculées par l'AFCM
donnees_clients <- res.mca$ind$coord

# 2. On teste de 2 à 10 groupes pour trouver le meilleur découpage
R2 <- data.frame(Nb_Groupes = 2:10, R_Carre = NA)

for (k in 2:10) {
  # nstart = 25 assure que le résultat est stable et fiable
  modele <- kmeans(donnees_clients, centers = k, nstart = 25)

  # R² = inertie inter-classe / inertie totale
  r_carre <- modele$betweenss / modele$totss

  R2$R_Carre[R2$Nb_Groupes == k] <- round(r_carre, 4)
}

# 3. Graphique pour repérer le "coude" (autour de 5 groupes)
plot(R2$Nb_Groupes, R2$R_Carre, type = "b", pch = 19, col = "blue",
     main = "Qualité de la segmentation (R²)",
     xlab = "Nombre de groupes", ylab = "R²")
grid()

# [AJOUT] K-means final à 5 groupes (utilisé pour la visualisation ci-dessous)
km5 <- kmeans(donnees_clients, centers = 5, nstart = 25)
groupes_km <- factor(km5$cluster)


# ---- 3. CAH (Classification Ascendante Hiérarchique, méthode de Ward) -------
# method = "ward" permet de créer des groupes compacts et homogènes
cah <- agnes(res.mca$ind$coord, diss = FALSE, metric = "euclidean",
             stand = FALSE, method = "ward")

# Affichage du dendrogramme
pltree(cah, cex = 0.6, hang = -1, main = "Dendrogramme (CAH - Ward)")

# On coupe l'arbre pour obtenir 5 familles de clients
groupes_cah <- cutree(cah, k = 5)
print(table(groupes_cah))
# Effectifs du rapport : 1 227 / 1 909 / 1 916 / 463 / 307
#   Groupe 1 : jeunes familles actives     -> potentiel futur
#   Groupe 2 : couples seniors modestes    -> potentiel faible
#   Groupe 3 : familles aisées (cible cœur)-> potentiel fort
#   Groupe 4 : isolés à faibles revenus    -> potentiel nul
#   Groupe 5 : profils atypiques           -> niche


# ---- 4. VISUALISATION DES GROUPES SUR LE PLAN FACTORIEL ---------------------
don_afcm2 <- donnees
don_afcm2$grp <- groupes_km  # (rapport : donnees$km)

# On relance une ACM spécifique pour projeter les groupes dessus
afcm2 <- MCA(don_afcm2, quali.sup = ncol(don_afcm2), graph = FALSE)

fviz_mca_var(afcm2, repel = TRUE)

# Affiche les individus colorés selon leur groupe d'appartenance
fviz_mca_ind(afcm2, label = "none", habillage = don_afcm2$grp,
             addEllipses = TRUE)

# [AJOUT] On conserve les groupes dans la table (colonnes présentes dans le
# fichier Top50_Clients_Prioritaires.csv)
donnees$Cluster <- groupes_km
donnees$Groupe  <- factor(groupes_cah)


# ---- 5. MODÉLISATION PRÉDICTIVE : RÉGRESSION LOGISTIQUE ---------------------
# Équilibrage : on prend tous les clients "Oui" et autant de "Non" tirés au hasard
don_ech <- donnees %>%
  group_by(Mobilhome) %>%
  slice_sample(n = min(table(donnees$Mobilhome))) %>%
  ungroup()
print(table(don_ech$Mobilhome))

# Découpage apprentissage / test : 80 % pour apprendre, 20 % pour vérifier
echantillon <- createDataPartition(don_ech$Mobilhome, p = 0.8, list = FALSE)
train <- don_ech[echantillon, ]
test  <- don_ech[-echantillon, ]

# Régression logistique : on explique Mobilhome par les variables
# socio-démographiques et les contrats détenus
formule <- Mobilhome ~ avgsiz + avgage + avgincom + Car + Third + Moto + Life + Accident
modele <- glm(formule, family = binomial(link = "logit"), data = train)

# Affiche les résultats (coefficients, p-values)
summary(modele)


# ---- 6. VALIDATION ET PERFORMANCES ------------------------------------------
# 1. Probabilités pour les clients du fichier TEST
test$prob <- predict(modele, newdata = test, type = "response")

# 2. Probabilité -> décision (seuil de 50 %)
test$prediction <- ifelse(test$prob >= 0.5, "Mobilhome_1", "Mobilhome_0")

# 3. Mise en forme obligatoire pour la fonction confusionMatrix
test$prediction <- factor(test$prediction, levels = levels(test$Mobilhome))

# 4. Matrice de confusion et taux de réussite
# [AJOUT] positive = "Mobilhome_1" : la "sensibilité" mesure alors les acheteurs
# correctement repérés (par défaut, R prend le 1er niveau, Mobilhome_0)
matrice <- confusionMatrix(data = test$prediction, reference = test$Mobilhome,
                           positive = "Mobilhome_1")
print(matrice)


# ---- 7. CIBLAGE DES PROSPECTS (TOP 50) --------------------------------------
# 1. Prospects = clients qui n'ont PAS l'assurance (Mobilhome_0)
prospects <- donnees[donnees$Mobilhome == "Mobilhome_0", ]
print(paste("Nombre de prospects à analyser :", nrow(prospects)))

# 2. Score = probabilité d'achat (entre 0 et 1) donnée par le modèle
prospects$SCORE <- predict(modele, newdata = prospects, type = "response")

# 3. Tri du plus "chaud" au plus "froid"
trie <- prospects[order(prospects$SCORE, decreasing = TRUE), ]

# 4. Sélection des 50 meilleurs
top_50 <- head(trie, 50)

# 5. Affichage des colonnes utiles pour voir POURQUOI ils sont choisis
colonne <- c("avgincom", "Car", "avgsiz", "SCORE")
print(top_50[, colonne])

write.csv(top_50, file = "Top50_Clients_Prioritaires.csv", row.names = FALSE)
